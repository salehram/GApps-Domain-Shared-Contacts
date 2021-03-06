#!/bin/bash
# This shell script provied as is, and I cannot provide any warranty or liability if it was used in the wrong way.
# I will try to keep a steady improvements on this script, and everyone is welcome to take it and change it the way they see more useful to them.
# This started as a very basic script to add shared contacts for Google apps, but it will get more features added by time, as I work on them slowly due to my real life obligations.
# -------------------------------------------------------------
echo -e "\n---------------------------------------------------------------------------------------------------------"
echo -e "------------------   Get-GSharedContacts (Version 0.0.2alpha) - saleh@is-linux.com   --------------------"
echo -e "---------------------------------------------------------------------------------------------------------\n"
echo -e "Preparing the required variables..."
echo -e "========================================================================================================="
echo -e "We will collect the following information:"
echo -e "    1. Client ID from the developer console, which you created earlier (if you read the README file)."
echo -e "    2. Client Secret from the developer console, which you created earlier (if you read the README file)."
echo -e "    3. The domain name of which you want to list its shared contacts."
echo -e "=========================================================================================================\n"
echo -e "Checking the supplied arguments..."
if [ $# -eq 0 ]; then
    echo ""
    echo "ERROR: No parameters were supplied, cannot continue!"
    echo "Usage instructions:"
    echo "Get-GSharedContacts [FULL_PATH_TO_CLIENT_SECRETS.JSON] [DOMAIN_NAME]"
    exit 1
fi
if [ $# -gt 2 ]; then
    echo ""
    echo "ERROR: Too many parameters were supplied, cannot continue!"
    echo "Usage instructions:"
    echo "Get-GSharedContacts [FULL_PATH_TO_CLIENT_SECRETS.JSON] [DOMAIN_NAME]"
    exit 1
fi
if [ $# -lt 2 ]; then
   echo ""
   echo "ERROR: Missing parameters"
   echo "Usage instructions:"
   echo "Get-GSharedContacts [FULL_PATH_TO_CLIENT_SECRETS.JSON] [DOMAIN_NAME]"
   exit 1
fi
# checking now for the JSON file if it is existing or not
jsonFile=$1
if [ ! -f $jsonFile ]; then
    # The JSON file is not available or wrong parameter was supplied
    echo "ERROR: Either JSON file not exists or wrong parameter supplied."
    exit 1
fi
#start working on the jSON file
echo "OK - Found JSON file, will start pulling data from it."
jsonData=`jq '.installed.client_id' $jsonFile`
clientID="${jsonData%\"}"
clientID="${clientID#\"}"
#client ID line
echo "     Retrieved client ID: $clientID"
jsonData=`jq '.installed.client_secret' $jsonFile`
clientSecret="${jsonData%\"}"
clientSecret="${clientSecret#\"}"
#client secret line
echo "     Retrieved client secret:" $clientSecret
#checking domain name
domainName=$2
echo -e "OK - Domain name is: $domainName"
echo -e "=========================================================================================================\n"
echo -e "Creating the authorization URL"
authURI="https://accounts.google.com/o/oauth2/auth?client_id=$clientID&redirect_uri=urn:ietf:wg:oauth:2.0:oob&response_type=code&scope=https://www.google.com/m8/feeds/"
echo -e "Please open your web browser and follow these instructions to grant us the required permissions:"
echo -e "    1. Copy the below link and once the page opens, sign in with your super admin account and grant the required permissions."
echo -e "    2. You will get an authorization code back from the page, please paste it here and press Enter/Return.\n"
echo -e "Copy below link:"
echo -e $authURI "\n"
#need to get the authorization code from user now
read -p "Please enter/paste the autorization code you got from the previous link: " authCode
#sending authorization code back and getting our token
tokenRequest=`curl -s -i -X POST https://www.googleapis.com/oauth2/v3/token -H "Content-Type: application/x-www-form-urlencoded" --data "code=$authCode&client_id=$clientID&client_secret=$clientSecret&redirect_uri=urn:ietf:wg:oauth:2.0:oob&grant_type=authorization_code"`
#reading the reeived access token and putting everything in one file
cat << EOF > tempToken.json
$tokenRequest
EOF
#extracing the line with the access token and put it in a new file with proper JSON formatting
tokenData=`cat tempToken.json | grep -E "access_token"`
cat << EOF  > token.json
{"token":{$tokenData"end":"end"}}
EOF
#now extract the token data and start use it.
APIToken=`jq '.token.access_token' token.json`
accessToken="${APIToken%\"}"
accessToken="${accessToken#\"}"
#rm -f tempToken.json
echo -e ""
echo -e "Received access token: $accessToken"
echo -e "=========================================================================================================\n"
echo -e "Getting the shared contacts using Google API"
status=0
pageNum=1
requestURL="https://www.google.com/m8/feeds/contacts/$domainName/full"
echo -en "id,updated,name,email" > $domainName-SharedContacts.csv
while [ $status -ne 1 ]; do
    echo `curl -i -s $requestURL -H "Authorization: Bearer $accessToken" > Get-GSharedContacts.output`
    #now we need to write the output data into the csv file
    readAtom () {
        local IFS=\>
        read -d \< ENTITY CONTENT
    }
    while readAtom; do
        if [[ $ENTITY = "id" ]]; then
            ExtraURL="http://www.google.com/m8/feeds/contacts/$domainName/base/"
            IDContent=${CONTENT#$ExtraURL}
            noLine=0
            if [[ $IDContent == "$domainName" ]]; then
                noLine=1
            fi
            if [[ $noLine != 1 ]]; then
                echo -en "\n$IDContent,"
            fi
        fi
        if [[ $ENTITY = "updated" ]]; then
            if [[ $noLine != 1 ]]; then
                echo -en "$CONTENT,"
            fi
        fi
        if [[ $ENTITY = "title type='text'" ]]; then
            if [[ $noLine != 1 ]]; then
                echo -en "$CONTENT,"
            fi
        fi
        if [[ $ENTITY = *"gd:email rel='http://schemas.google.com/g/2005#work' address"* ]]; then
            prefix="gd:email rel='http://schemas.google.com/g/2005#work' address='"
            suffix="' primary='true'/"
            email=${ENTITY#$prefix}
            email=${email%$suffix}
            if [[ $noLine != 1 ]]; then
                echo -en "$email"
            fi
        fi
    done < Get-GSharedContacts.output >> $domainName-SharedContacts.csv
    #
    #checking to see if we have more pages in the returned result
    nextPage=$(cat Get-GSharedContacts.output | grep -Po "<link rel='next' type='application\/atom\+xml' href(.*?)\/>")
    if [[ ! "$nextPage" ]] ; then
        echo -e "\n"
        echo -e "========================"
        echo -e "Finished adding contacts... cleaning up and ending"
        echo -e "   - Out file is: $domainName-SharedContacts.csv"
        echo -e "   - Operation log file is: Get-GSharedContacts.output"
        rm -f tempToken.json
        rm -f token.json
        status=1
        exit 0
    else
        nextPageLink=$(echo $nextPage | grep -Po "https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#;?&//=]*)")
        requestURL=$nextPageLink
        status=0
        let pageNum=$pageNum+1
        echo -n "We got more pages. Retrieveing page number $pageNum"
    fi
done
