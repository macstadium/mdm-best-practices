#!/bin/bash
###############################################################################
# enable_remote_access.sh
#
# Triggered by Jamf Pro enrollment complete policy.
# - Enables SSH (Remote Login) directly via systemsetup
# - Calls the Jamf Pro API to send the Enable Remote Desktop MDM
# command to this device using its own serial number for lookup
#
# Parameters:
# $4 - Jamf Pro API Client ID
# $5 - Jamf Pro API Client Secret
# $6 - Jamf Pro URL (e.g. https://yourinstance.jamfcloud.com)
###############################################################################
CLIENT_ID="$4"
CLIENT_SECRET="$5"
JAMF_URL="$6"
if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" || -z "$JAMF_URL" ]]; then
echo "ERROR: Missing required parameters."
exit 1
fi
JAMF_URL="${JAMF_URL%/}"
# Enable SSH locally -- no MDM command required
echo "Enabling SSH (Remote Login)..."
/usr/sbin/systemsetup -setremotelogin on
if [[ $? -eq 0 ]]; then
echo "SSH enabled."
else
echo "WARNING: systemsetup returned an error. SSH may not be enabled."
fi
# Get bearer token
echo "Requesting API token..."
TOKEN_RESPONSE=$(curl -s -X POST "$JAMF_URL/api/oauth/token" \
-H "Content-Type: application/x-www-form-urlencoded" \
-d "client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&grant_type=client_credentials")
TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
if [[ -z "$TOKEN" ]]; then
echo "ERROR: Failed to obtain API token."
echo "Response: $TOKEN_RESPONSE"
exit 1
fi
echo "Token obtained."
# Get this device's serial number
SERIAL=$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $4}')
if [[ -z "$SERIAL" ]]; then
echo "ERROR: Could not determine serial number."
exit 1
fi
echo "Serial number: $SERIAL"
# Brief pause for Jamf DB write lag after enrollment
sleep 20
# Look up Jamf device ID by serial number
echo "Looking up Jamf ID for serial $SERIAL..."
COMPUTER_XML=$(curl -s \
-H "Authorization: Bearer $TOKEN" \
-H "Accept: application/xml" \
"$JAMF_URL/JSSResource/computers/serialnumber/$SERIAL")
COMPUTER_ID=$(echo "$COMPUTER_XML" | xpath -q -e "//computer/general/id/text()" 2>/dev/null)
if [[ -z "$COMPUTER_ID" ]]; then
echo "ERROR: Could not find Jamf ID for serial $SERIAL."
exit 1
fi
echo "Jamf ID: $COMPUTER_ID"
# Send Enable Remote Desktop MDM command via Jamf API
echo "Sending Enable Remote Desktop command..."
COMMAND_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
-H "Authorization: Bearer $TOKEN" \
"$JAMF_URL/JSSResource/computercommands/command/EnableRemoteDesktop/id/$COMPUTER_ID")
if [[ "$COMMAND_RESPONSE" == "201" ]]; then
echo "SUCCESS: Enable Remote Desktop command queued for device ID $COMPUTER_ID."
exit 0
else
echo "ERROR: API returned HTTP $COMMAND_RESPONSE."
exit 1
fi