    #<BEGIN_SCRIPT>#
     
    <#
     
    .SYNOPSIS
    This is a Powershell script to perform mass AD user attribute changes.
     
    .DESCRIPTION
    Mass user attribute changes. Changes a selected attribute for multiple, or all, AD Users in domain.
     
    The script prompts the user for an attribute name. This is the name of the AD user attribute to be changed. 
    Run "Get-ADUser <Any_SamAccountName> -Properties *" for a full list of attributes.
     
    Then, the script prompts for the value you would like to set the attribute too. You can include variables in 
    the value by adding them to the script. See both the comments in the "ADD YOUR OWN VARIABLES HERE" section 
    of the function MakeChanges, and the comments for the ValueMenu function for more information. 
     
    Next, the script prompts for whether or not you would like to include a -SearchBase, an Organizational Unit (OU) 
    to include users from. Selecting to not use a search base will use the root domain DistinguisedName (DN). Selecting
    to include a search base will prompt you to select the desired OU from a table using Out-GridView.
     
    Then, the script prompts for a -Filter to include with Get-ADUser. You can select from a preset filter template, 
    or you can enter a custom filter. This determines which AD user accounts are gotten.
     
    Finally, the script runs through multiple verification processes, prompting you to verify all of the information,
    the list of AD users to be changed, and the changed attributes before it pushes the changes to the AD users.
     
    .INPUTS
        This script does not accept any inputs. All information is passed interactively. 
     
    .OUTPUTS
        This script does not create any output.
     
    .EXAMPLE
        'Mass User Attribute Change.ps1'
        Change the description attributes to give the date the AD user was modified and who modified it.
        Change all users in the OU named 'PEBKAC' in domain 'contoso.com'.
     
        Attribute = description
        Value = Modified on $date by $env:USERNAME
        SearchBase = OU=PEBKAC,DC=contoso,DC=com
        Filter = '*'
     
    .EXAMPLE
        'Mass User Attribute Change.ps1'
        Reset the pwdLastSet attribute for all users who have not logged in to their accounts in the past 90 days.
     
        Attribute = pwdLastSet
        The value will be automatically preset to @("0","-1") if you select pwdLastSet as the attribute
        Select not to use a SearchBase
        Filter = "lastLogonDate -le '$($date.AddDays(-90))'"
     
    .EXAMPLE
        'Mass User Attribute Change.ps1'
        Set the mail attribute on all users created in the last 7 days in the OU named 'Students'. 
        The domain is 'school.com' and the username uses the following scheme: 
        'first 6 letters of the last name (or the entire last name if it is shorter)'
        'first 2 letters of the first name'
        'last 2 digits of their graduation year (stored as a 4 digit number in the Department attribute)'
     
        The following variables are added in the MakeChanges function in the script:
        $domain = "@school.com"
        $lastName = $($user.surName.Substring(0,[Math]::Min(6, $user.surName.Length))) 
        $firstName = $($user.GivenName.Substring(0,2))
        $department = $($user.Department.Substring(2))
        $username = '{0}{1}{2}' -f $lastName,$firstName,$department
        $emailaddress = '{0}{1}' -f $username,$domain
        $myAttributes = "givenName,surName,Department"
     
        Attribute = mail
        Value = $emailaddress
        SearchBase = OU=Students,DC=school,DC=com
        Filter = "whenCreated -ge '$($date.AddDays(-7))'"
     
    .EXAMPLE
        'Mass User Attribute Change.ps1'
        Change the description to "IT testing" for any users with 'test' anywhere in their SamAccountName. 
     
        Attribute = description
        Value = IT testing
        No SearchBase
        Filter = "SamAccountName -like '*test*'"
     
    .NOTES
        Author: Eric Claus
        Last Modified: 5/22/2017
     
    .LINK
    https://gallery.technet.microsoft.com/scriptcenter/Change-AD-Attribute-e5525647
     
    .COMPONENT
    Get-ADUser, Set-ADUser
     
     
    #>
     
    ############ TO-DO ############
    # -Add email notification feature
    # -Add ability to import a list of users, instead of using a -Filter or -SearchBase
    ###############################
     
    ########### To add your own variables, see the MakeChanges function below. ###########
     
    ###### Required Module ######
    Import-Module ActiveDirectory 
     
    # Declare date variable to include in the log file name.
    $dateString = (Get-Date).ToString('MM-dd-yyyy_HH-mm-ss')
    # Declare date variable to use for calculating dates
    $date = Get-Date
    # Create log file in the same directory the script is located in, with the date and time.
    $logfile = "$PSScriptRoot\Mass_User_Change_Log($dateString).log"
    # Echo to the log the date and the username and computer name of the user running the script.
    echo "Date: $(Get-Date -Format G), User: $Env:UserName, Computer: $Env:ComputerName" >>$logfile
     
    #####<BEGIN_FUNCTION_DEFINITIONS>#####
     
    ## Select which attribute to change. Returns the attribute as a string named $attribute.
    function AttributeMenu {
        # Present the user with a menu of preset attributes to choose from. User may also enter a custom attribute.
        $menuSelection = Read-Host "Please select from one of the following attributes to edit.
     
        1) pwdLastSet - Reset pwdLastSet to the current date, extending the password expiration date
        2) Description - Change the description 
        3) Mail - Change the email address
        4) Enabled - Enable or disable account <True|False>
        5) SamAccountName - Change the SamAccountName (username)
        6) Other - Careful!
     
        Select from the list (1-5)"
     
        # Evaluates the user's input ($menuSelection) and if they selected a valid menu option (an int from 1-5),
        # assigns the cooresponding attribute name to $attribute.
        Switch ($menuSelection) {
            1 {$script:attribute = 'pwdLastSet'}
            2 {$script:attribute = 'description'}
            3 {$script:attribute = 'mail'}
            4 {$script:attribute = 'enabled'}
            5 {$script:attribute = 'SamAccountName'}
            6 {$script:attribute = Read-Host "Please enter an attribute name"} # Read user's input into $attribute
            # If the user's input is not a valid menu choice, loop back through the function again.
            default {echo "`nError: Select a valid menu option.`n"; AttributeMenu}
        }
    }
     
    ## Select what value(s) to set the attribute to. Returns either string or array $value.
    ## This $value is what the selected AD users' $attribute wil be set to. 
    function ValueMenu {
        # Determines what to set $value to based on which attribute is being modified.
        Switch ($attribute) {
            # If the attribute is 'pwdLastSet', the pwdLastSet values to accomplish this are hard coded in here as an array.
            # This, and subsequently why the script is made to support arrays of values, is because resetting the pwdLastSet 
            # attribute in order to extend the password expiration date of the AD user account was the original purpose of this script.
            pwdLastSet {
                        $script:value = @("0","-1")
                       }
            # If the attribute is 'Enabled' only two values are valid, 'True' (enabled) and 'False' (disabled).
            # The user is prompted to select which one they would like to use.
            enabled    {
                        $ui = Read-Host "Would you like to enable (set value to 'True') or disable (set value to 'False')? <enable|disable>"
                        if ($ui -eq "enable" -or $ui -eq 'true') {$script:value = "True"}     
                        elseif ($ui -eq "disable" -or $ui -eq "false") {$script:value = "False"}
                        else {echo "Error: Enter either 'enabled', 'true', 'disabled', or 'false'"; ValueMenu}
                        }                     
            default    {
                        echo "Please type a value you would like to set $attribute to. Can be a variable."
                        echo "To include a user attribute that you specified in the `$myAttributes variable ($myAttributes),"
                        echo "use the format `$(`$user.<attribute_name>). Run Get-Help '$PSCommandPath' for more info.`n"
                        $script:value = (Read-Host "Please type the value you would like to set $attribute to (do not enclose in quotes)")
                       }
        }
    }
     
    ## Define a search base to be used with Get-ADUser. Selects which, if any, OU to search in. Returns string $searchBase with either
    ## the OU's DN, or the DN of the root domain.
    function SearchBaseMenu {
        # Asks user if they want to use a -SearchBase or not.
        $useSearchBase = Read-Host "`nWould you like to include a -SearchBase (a specific OU to get users from)? <yes|no>"
     
        # If the user decides to include a -SearchBase, they are prompted to select an OU to use.
        if ($useSearchBase -eq "yes") {
            echo "Please select from the following list of OUs to use as your search base."
     
            # Queries AD for all OUs, selects the Name and DN of each OU, and sends them to Out-GridView, a sortable table in a popup
            # window. -OutputMode Single allows one of the rows (i.e. OUs) to be selected and returned as input into another variable.
            # For the purpose of this script, it allows the selected OU to be assigned to $script:searchBase. 
            $script:searchBase =  (Get-ADOrganizationalUnit -Filter * | select Name,DistinguishedName | 
                Out-GridView -Title "Select an OU that you would like to search and press 'OK'." -OutputMode Single).DistinguishedName        
     
        # If the user did not select an OU from the list, repeate SearchBaseMenu
        if (-Not $searchBase) {echo "`nError: OU not selected.`n"; SearchBaseMenu}
        }
     
        # If the user decides not to include -SearchBase and instead search the entire domain, the DN of the domain is used instead.
        elseif ($useSearchBase -eq "no") {$script:searchBase = "$(Get-ADDomain)"}
     
        # If user neither enters 'yes' or 'no', they are sent back to the begining of this function.
        else {echo "`nError: Enter either 'yes' or 'no'`n"; SearchBaseMenu}
    }
     
    ## Define a filter to be used with Get-ADUser. Selects which AD users to get. Returns string $userFilter.
    function FilterMenu {
        # Display a menu with several preset user filters. User can choose from the presets or enter their own.
        $menuSelection = Read-Host "Please select from the following list of filters, or specify your own.
            You will be asked to enter the portion in < > next.`n
            1)Name -eq '<full name>'
            2)Name -like '<full name (supports the * wildcard)>'
            3)SamAccountName -eq '<username>'
            4)SamAccountName -like '<username (supports the * wildcard)>'
            5)surName -eq '<last name>'
            6)givenName -eq '<first name>'
            7)lastLogonDate -le '`$(`$Date.AddDays(-<number of days>))'
            8)passwordLastSet -le '`$(`$Date.AddDays(-<number of days>))'
            9)adminCount -eq '<0|1>'
            10)*
            11)Other`n
        Select from the list (1-11)"
     
        echo ""
     
        # Evaluates the user's input ($menuSelection) to determine which, if any, of the menu options the user selected.
        # Cases 1-9 prompt the user to enter the variable part of the user filter ($searchTerm) and then place $searchTerm
        # into the preset portion of the filter string, creating $userFilter with the complete filter string.
        Switch ($menuSelection) {
            1 {
                $searchTerm = Read-Host "Please enter a name to be put in the filter: 
                    Name -eq <full name>"
                $script:userFilter = "Name -eq '$searchTerm'"}
            2 {
                $searchTerm = Read-Host "Please enter a name to be put in the filter: 
                    Name -like <full name (supports the * wildcard)>"
                $script:userFilter = "Name -like '$searchTerm'"}
            3 {
                $searchTerm = Read-Host "Please enter a username to be put in the filter: 
                    SamAccountName -eq <username>"
                $script:userFilter = "SamAccountName -eq '$searchTerm'"}
            4 {
                $searchTerm = Read-Host "Please enter a username to be put in the filter: 
                    SamAccountName -like <username (supports the * wildcard)>"
                $script:userFilter = "SamAccountName -like '$searchTerm'"}
            5 {
                $searchTerm = Read-Host "Please enter a name to be put in the filter: 
                    surName -eq <last name>"
                $script:userFilter = "Surname -eq '$searchTerm'"}
            6 {
                $searchTerm = Read-Host "Please enter a name to be put in the filter: 
                    givenName -eq <first name>"
                $script:userFilter = "givenName -eq '$searchTerm'"}
            # Cases 7 and 8 - checks if user's input is an int or floating point and repeats if it is not. 
            7 {
                $searchTerm = Read-Host "Please enter a number of days to be put in the filter (how many days ago was the last log on): 
                    lastLogonDate -le `$(`$date.AddDays(-<number of days>))"
                if ($searchTerm -notmatch "^[\d\.]+$") {echo "`nError: Enter a numeric value`n"; FilterMenu}
                $script:userFilter = "lastLogonDate -le '$($date.AddDays(-$searchTerm))'"}
            8 {
                $searchTerm = Read-Host "Please enter a number of days to be put in the filter (how many days ago was the password last set): 
                    passwordLastSet -le `$(`$date.AddDays(-<number of days>))"
                if ($searchTerm -notmatch "^[\d\.]+$") {echo "`nError: Enter a numeric value`n"; FilterMenu}
                $script:userFilter = "passwordLastSet -le '$($Date.AddDays(-$searchTerm))'"}
            # Prompts the user to select whether to search for admin or non-admin accounts via attribute adminCount.
            9 {
                $searchTerm = Read-Host "Please select from the below options:`n
                        1) Search for only admin accounts
                        2) Search for only non-admin accounts`n"
     
                # Checks the user's input and matches it to one of the two options below. 
                switch ($searchTerm) {
                    1 {$script:userFilter = "adminCount -eq '1'"}
                    # Based on Byron Wright's blog http://byronwright.blogspot.com/2012/09/filtering-for-null-values-with-get.html
                    2 {$script:userFilter = "adminCount -notlike '*'"}
                    default {"`nError: Enter a valid menu option (1 or 2)"; FilterMenu}}}
     
            # If user selections menu option 10, "*", to get all AD users, no user input is needed.
            10 {
                $script:userFilter = "*"}
     
            # Read user's input into $userFilter        
            11 {
                $script:userFilter = Read-Host "Please specify a filter for which users are gotten.`n 
        Examples: 'Surname -eq claus' - gets all users with lastname 'claus'; 
                  'lastLogonDate -le `$(`$Date.AddDays(-90))' - gets all users who have not logged on in the past 90 days
                  'samaccountname -like 'testits*' - gets all users with SamAccountName begenning with 'testits'
                  'name -like 'eric*' - gets all users whose names start with 'eric'
                  '*' - get all AD users (WARNING: CAREFUL!)`n
                  Please specify a filter"}
            # If the user's input is not a valid menu choice, repeat the menu.
            default {echo "`nError: Enter a valid menu choice.`n"; FilterMenu}}
    }
     
    ## Have the user verify all of the supplied information is correct. If the user does not verify the info, 
    ## the script exits. If info is correct, the info is logged and the script continues.
    function VerifyInfo {
        # Displays the information provided by the user ($attribute, $value, $userFilter, and $OU) for verification
        echo "Please verify all of the below information is correct.`n"
        echo "User attribute to be changed:      $attribute" 
        echo "Value(s) to set the attribute to:  $value"
        echo "User filter:                       $userFilter"
        echo "Search base (OU):                  $searchBase`n"
        echo "If the above information is correct, users matching the filter '$userFilter' in the OU '$searchBase' 
        will have their '$attribute' attribute changed to '$value'.`n"
     
        $verifyInfo = Read-Host "If this is correct enter 'yes', if this is not correct enter 'no'"
     
        # If the info is correct, record the information in the log.
        if ($verifyInfo -eq "yes") {
            echo "Information verified as being correct." >>$logfile 
            echo "<BEGIN_INFO_LIST>" >>$logfile
            echo "Attribute=$attribute" >>$logfile
            echo "Value=$value" >>$logfile
            echo "Filter=$userFilter" >>$logfile
            echo "SearchBase=$searchBase" >>$logfile
            echo "<END_INFO_LIST>" >>$logfile
        }
        # Exit script to DisplayHelp if supplied information is not correct, log the error.
        else {
            echo "Information not verified as being correct" >>$logfile
            echo "`nExiting script...`nRun Get-Help '$PSCommandPath' for help."
            Exit
        }
    }
     
    ## Have the user verify that the list of users gotten ($userList) is correct. If the user does not verify the list of users, 
    ## the script exits. If the user list is correct, it is logged and the script continues.
    function VerifyUserList {
        echo "`nPlease verify the User Filter is correct and that the list of affected users is correct." 
        echo "In the popup box, press OK if the list of users is correct, press Cancel if it is not.`n"
        pause
     
        # Send the list of AD users ($userList) to Out-GridView which displays the AD users as a sortable table in a popup window.
        # The -Title flag sets the title of the window to be displayed at the top. -OutputMode Single allows one of the rows to be
        # selected and returned as input into another variable. For the purpose of this script, it allows data to be returned to
        # $userVerify2 if the user presses "OK" in the popup window, signifing they have confirmed that the list of AD users is correct.
        # If the user presses "Cancel" in the popup window, no data is returned and the list of AD users is not verified. 
        $verifyUsers = $userList|select $finalAttributes|Out-GridView -Title "Press OK if correct, Cancel if not correct" -OutputMode Single
     
        # Checks if data was returned to $verifyUsers (i.e. the user confirmed that the list of AD users is correct and pressed OK).
        # Sends the list of AD users to the log.
        if ($verifyUsers) {
            echo "List of affected users verified as being correct." >>$logfile
            echo "<BEGIN_INITIAL_USER_LIST>" >>$logfile
            echo $userList | select $finalAttributes >>$logfile
            echo "<END_INITIAL_USER_LIST>" >>$logfile
        }
        # If $verifyUsers is empty (i.e. the user did not confirm that the list of AD users is correct and pressed Cancel), 
        # logs it and exits the script.
        else {
            echo "List of affected users not verified as being correct." >>$logfile
            echo "`nExiting script...`nRun Get-Help '$PSCommandPath' for help."
            Exit
        }
    }
     
    ## Pushes the changes to AD. 
    ## Thanks to Hofsteenge for his Change_User_pwdlastset.ps1 from which this is based.
    function MakeChanges {
        # Initialize counters to track progress.
        $numUsersModified = 0
        $numUsersChanged = 0
        $numTotalUsers = ($userList).count
     
        # This is where the change occurs. Loops through the list of users ($userList) to be changed.
        ForEach ($user in $userList) {       
     
            <############## ADD YOUR OWN VARIABLES HERE #############
            Add any variables here that you would like to use in the attribute's value string. If the desire variable is an
            existing AD user attribute (e.g. Department, whenCreated, etc.), add the attribute name(s) to the $myAttributes
            string below. Seperate each attribute with a comma. When defining the variables in the value string, reference them
            as $($user.attribute_name) (e.g. $($user.givenName)). SamAccountName is already returned and does not need to be added.
            The examples below set the mail attribute to the first 6 letters of the user's last name (or their entire last name if it
            is shorter than 6 letters), the first 2 of their first name, their department number, and with the domain '@foo.com':
     
            $domain = "@foo.com"
            $lastName = $($user.surName.Substring(0,[Math]::Min(6, $user.surName.Length))) 
            $firstName = $($user.GivenName.Substring(0,2))
            $department = $($user.Department)
            $username = '{0}{1}{2}' -f $lastName,$firstName,$department
            $emailaddress = '{0}{1}' -f $username,$domain
            $myAttributes = "givenName,surName,Department"
            The $emailaddress would be entered for the value when the script is run.
            #>
     
     
     
            $myAttributes = ""
            #######################################################
     
          # Loop through the value(s) specified in $value (if multiple values are specified)
          ForEach ($j in $value) {
            # Read-Host interperets everything as a literal string. Variables, therefore, are treated as strings and are not expanded.
            # This command takes the value string as gotten from Read-Host and manually expands it so that variables work correctly.
            $expandValue = $ExecutionContext.InvokeCommand.ExpandString($j)
            # The current AD user's desired attribute is set to the value string ($value) that has now been expanded ($expandValue).
            $user.$attribute = "$expandValue" 
          }
          $numUsersModified++
          echo "User: $numUsersModified / $numTotalUsers"
        }
     
        echo "Please verify the changes are correct and press OK to push the changes to AD."
        pause
        $verifyChanges = $userList | select $finalAttributes | Out-GridView -Title "Press OK to confirm the changes" -OutputMode Single
     
        if ($verifyChanges) {
            # Write the changes to AD
            ForEach ($user in $userList) {
                Set-ADUser -Instance $user
                $numUsersChanged++
                echo "Setting user: $numUsersChanged / $numTotalUsers"
            }
     
            # Logs the affected AD users with their updated $attribute.
            echo "Changes have been verified.`n<BEGIN_FINAL_USER_LIST>" >>$logfile
            $finalUserList = Get-ADUser -Filter $userFilter -SearchBase $searchBase -Properties $finalAttributes | select $finalAttributes
            echo $finalUserList >>$logfile
            echo "<END_FINAL_USER_LIST>" >>$logfile
     
            $finalUserList | Out-GridView -Title "Updated list of AD Users"
        }
        else {
                echo "Error: Changes not verified." >>$logfile
                echo "`nError: Changes not verified.`nExiting script...Run Get-Help '$PSCommandPath' for help."
                Exit
             }  
    }
     
    #####<END_FUNCTION_DEFINITIONS>#####
     
    #####<BEGIN_MAIN>#####
     
    # Have the user specify the attribute to be changed. Returns string $attribute.
    AttributeMenu
    clear
     
    # Have the user specify the value to set $attribute to. Returns either string or array $value.
    ValueMenu
    clear
     
    # Have the user specify what, if any, -SearchBase to use with Get-ADUser. Returns string $searchBase. 
    SearchBaseMenu
    clear
     
    # Have the user specify what -Filter to use with Get-ADUser. Returns string $userFilter.
    FilterMenu
    clear
     
    # Has the user verify that the $attribute, $value, $userFilter, and $searchBase are all correct and logs the info if so. 
    # Exits script if the info is not verified as being correct.
    VerifyInfo
    Clear
     
    # Prepends SamAccountName and $attribute onto the string $myAttributes if user has manually added attributes to it at the
    # beginning of this script. The Split method is called to seperate the string into an array of strings.
    if ($myAttributes) {
        $finalAttributes = "SamAccountName,$attribute,$myAttributes"
        $finalAttributes = $finalAttributes.Split(',')
    }
    else {$finalAttributes = "SamAccountName,$attribute"}
     
    # Query AD to get the selected AD users' names and their selected attributes. Adding the desired attribute to -Properties 
    # guarantees that property will be pulled from AD. Based on Hofsteenge's Change_User_pwdlastset.ps1 
    $userList = Get-ADUser -Filter $userFilter -SearchBase $searchBase -Properties $finalAttributes
     
    # Has the user verify that the list of users gotten from AD ($userList) is correct and logs the user list if so. 
    # Exits script if the user list is not verified as being correct.
    VerifyUserList
    Clear
     
    echo "`nAll information has been verified. Proceeding to make the requested changes.`n"
     
    # Loops through the AD users in $userList and changes their $attribute to the new $value.
    # Logs the list of AD users with their new $attribute values.
    MakeChanges
     
    #<END_SCRIPT>#

