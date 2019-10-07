##// 



function getValidCredentials() {
    $validCredentials = $false

    $credentials = ''

    While($validCredentials -eq $false){
        if($credentials = $host.ui.PromptForCredential("Need credentials", "Please enter your user name and password.", "", "")){}else{exit}

        $CurrentDomain = "LDAP://" + ([ADSI]"").distinguishedName
        $domain = New-Object System.DirectoryServices.DirectoryEntry($CurrentDomain,$credentials.UserName,$credentials.GetNetworkCredential().Password)

        if ($domain.name){
            $validCredentials = $true
        }
        else{
            Write-Host ''
            Write-Host 'Invalid credentials, please try again'
            Write-Host ''
        }
    }

    return $credentials
}

##// 

$targetSystems = (
    '')

$credentials = getvalidCredentials

##//

foreach($targetSystem in $targetSystems){
    try {      
        Invoke-Command -ComputerName $targetSystem -SessionOption (New-PSSessionOption -NoMachineProfile) -ArgumentList $credentials, $targetSystem -ScriptBlock {  

            Write-Host "`ntargetSystem: " $args[1] "`n"

            $credentials = $args[0]
            $targetSystem = $args[1]

            Try
            {            
                ###### Updating Services ######

                Write-Host 'Updating password on' $targetSystem 'for services running under' $credentials.UserName "`n"
                
                $services = Get-WmiObject win32_service | Where startname -Like $credentials.UserName | select-object name, displayname, startname

                foreach($service in $services) {

                    ##//
                                    
                    Write-Host 'Service: ' $service.displayname
                    $input = Read-Host -Prompt 'Update with new password? (y/n)'
                    Write-Host ''

                    if($input.ToLower() -ne 'y'){ continue }

                    $serviceName = $service.Name

                    ##//

                    Write-Host "Stopping Service '$serviceName'"

                    $serviceToUpdate = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
        
                    $serviceToUpdate.StopService()

                    while ($serviceToUpdate.State -ne "Stopped") {
                        Start-Sleep -s 1
                        $serviceToUpdate = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
            
                        Write-Host "Waiting to stop..."
                        Write-Host "Current Status: " $serviceToUpdate.State
                    }    

                    ##//            

                    $serviceToUpdate.Change($null,
                                $null,
                                $null,
                                $null,
                                $null,
                                $null,
                                $credentials.UserName,
                                $credentials.GetNetworkCredential().Password)

                    ##//

                    Write-Host "Starting Service '$serviceName'"

                    $serviceToUpdate = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"

                    $serviceToUpdate.StartService()

                    $startAttempts = 0

                    while ($serviceToUpdate.State -ne "Running") {

                        if($startAttempts -eq 20) { 
                            Write-Host 'Unable to start: ' $serviceName
                            Break 
                        }

                        Start-Sleep -s 1
                        $serviceToUpdate = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
            
                        Write-Host "Waiting to start..."
                        Write-Host "Current Status: " $serviceToUpdate.State
                        $startAttempts++
                    }
                }           
                        
                ###### Updating Application Pools ######

                Write-Host "`nUpdating password on" $targetSystem "for app pools running under" $credentials.UserName "`n"

                if (Get-Module -ListAvailable -Name WebAdministration) {

                    Import-Module -Name WebAdministration
                    $appPools = Get-ChildItem -Path IIS:\AppPools | select-object name, processModel

                    foreach($appPool in $appPools){                          
                        $processModel = $appPool.processModel
                        $identity = $processModel.Username
                        $appPoolName = $appPool.name
        
                        if($identity -Like $credentials.UserName){
                            ##//
        
                            $identityType =  $processModel.identityType
                            
                            Write-Host 'App-Pool: ' $appPoolName
                            $input = Read-Host -Prompt 'Update with new password? (y/n)'
                            Write-Host ''
        
                            if($input.ToLower() -ne 'y'){ continue }
        
                            $temppool = get-item iis:\apppools\$appPoolName;
                            $tempPool.processModel.password = $credentials.GetNetworkCredential().Password;
                            $tempPool | Set-Item
        
                            ##//
        
                            Write-Host "Stopping app-pool $appPoolName"
        
                            Stop-WebAppPool -Name $appPoolName
        
                            ##//
        
                            Write-Host "Starting app-pool (waiting for 15 seconds)"
                            Start-Sleep -s 15
        
                            Start-WebAppPool -Name $appPoolName
        
                            $startAttempts = 0
        
                            while ((Get-WebAppPoolState $appPoolName).Value -ne 'Started')
                            {
                                if($startAttempts -eq 20) { 
                                Write-Host 'Unable to start: ' $appPoolName
                                Break 
                                }
        
                                Start-Sleep -s 1
                
                                Write-Host "Waiting to start..."
                                $startAttempts++
                            }
                        }         
                    }                  	
                } 
                else {
                    Write-Host "WebAdministration Module does not exist: $targetSystem doesn't have any app pools to restart"
                }				
            }
            Catch [system.exception]
            {
                $ErrorMessage = $_.Exception.Message
                $Stacktrace = $_.Exception.StackTrace	
                write-host "Error" $ErrorMessage
                Write-Host $Stacktrace
            }
            Finally
            {
                Write-Host 'Finished with $targetSystem ....'
            }
        }
    }
    catch {
        Write-Host 'Unable to connect to $targetSystem ....'
    }
}



