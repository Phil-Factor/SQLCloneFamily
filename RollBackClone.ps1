<# fill these values with the name of the clone that you want to revert/reset; a clone 
is best identified by its NetName (server) and database #>
$Reset = @{
  'Database' = 'AdventureWorksOurs';
  'Server' = 'MyServer'
}

$VerbosePreference = "Continue"
<# 
 
#>
# set "Option Explicit" to catch subtle errors
set-psdebug -strict
$ErrorActionPreference = "stop"

<# just to make it easier to understand, the various parameter values are structured in a 
hierarechy. We iterate over the clones when making or updating them #>
$Errors = @()
#First we read in the configuration from a file (do it so we can use the ISE as well)
<# first, find out where we were executed from #>
try
{ $executablepath = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition) }
catch
{
  $executablepath = "$(If ($psISE)
    { Split-Path -Path $psISE.CurrentFile.FullPath }
    Else { $global:PSScriptRoot })"
}

$Data = &"$executablePath\CloneConfig.ps1"
<# we read in the data as a structure. #>
$NoSqlCompare = $True;
if ($data.tools.SQLCompare -ne $null)
#we define the SQLCompare alias to make calling it easier
{
  Set-Alias SQLCompare $data.tools.SQLCompare -Scope Script
  $NoSqlCompare = $false;
}
else
{
  Write-Warning "We assume you don't want to do a comparison to ensure that any existing work is saved.";
  $NoSqlCompare = $true
}
<#connect to clone #>

Connect-SQLClone -ServerUrl $data.Image.ServerURL   `
         -ErrorAction silentlyContinue   `
         -ErrorVariable +Errors
if ($Errors.count -eq 0)
{
  $image = Get-SqlCloneImage -Name $data.Image.Name    `
                 -ErrorAction silentlycontinue    `
                 -ErrorVariable +Errors
  
  if ($Errors.Count -gt 0)
  { Write-Warning "The image $data.Image.Name can't be found" }
}
<# now we need to find out the clone that we need to use to compare with the clone
that we want to revert to save any differences. #>

if ($Errors.count -eq 0)
{
  $originalClone = @()
  $data.clones | foreach {
    if ($_.IsOriginal -eq $true)
    { $originalClone = $_ };
    if ($_.database -eq $Reset.Database -and $_.NetName -eq $Reset.Server)
    { $ResetClone = $_ }
  }
<# check that we have got everything correctly #>
  if ($originalClone.IsOriginal -ne $true)
  {
    $errors += 'You have not defined which clone represents the original'
  }
  if ($ResetClone.database -ne $Reset.Database -or $ResetClone.NetName -ne $Reset.Server)
  {
    errors+=  'You have not defined which clone represents the one you wish to reset'
  }
  
}
<# save any schema differences between the two #>
if ($Errors.count -eq 0)
{
  # we need to get hol;d of the passwords for any connection that has a userid
  # attached to it. We save these in a file within the user area, relying on NTFS security and 
  # encryption (gulp)
  @($ResetClone, $OriginalClone) | foreach{
    if ($_.username -ine '')
    {
      #create a connection object to manage credentials
      $encryptedPasswordFile = "$env:USERPROFILE\$($_.username)-$($_.Netname).txt"
      # test to see if we know about the password un a secure string stored in the user area
      if (Test-Path -path $encryptedPasswordFile -PathType leaf)
      {
        #has already got this set for this login so fetch it
        $encrypted = Get-Content $encryptedPasswordFile | ConvertTo-SecureString
        $_.Credentials = New-Object System.Management.Automation.PsCredential($_.username, $encrypted)
      }
      else #then we have to ask the user for it
      {
        #hasn't got this set for this login
        $_.Credentials = get-credential -Credential $Username
        $_.Credentials.Password | ConvertFrom-SecureString |
        Set-Content "$env:USERPROFILE\$SourceLogin-$SourceServerName.txt"
      }
      
    }
  }
  if ($resetClone.Nocheck -ne $true -and $NoSqlCompare -eq $false)
  {
    write-verbose "checking whether anything has changed on clone $($ResetClone.Netname) $($ResetClone.Database) compared with  $($OriginalClone.Netname) $($OriginalClone.Database)"
    <# make sure all the connections are servicable #>
  
    #Now we have the connection information 
    #we need to make sure that the work directory is there and
    # also that there isn't a script file  there already. 
    if (-not (Test-Path -PathType Container "$($data.WorkDirectory)"))
    {
      New-Item -ItemType Directory -Force -Path "$($data.WorkDirectory)" `
           -ErrorAction silentlycontinue -ErrorVariable +Errors;
    }
    if ($ResetClone.AfterCreateScripts -ne $null)
        {write-warning "Your Clone $($ResetClone.Netname) $($ResetClone.Database) has one or more raw scripts to execute. 
         If they are database changes, these will show up in the comparison!"}
    $OutputMigrationScript = "$($data.WorkDirectory)\$($ResetClone.Database)-$($OriginalClone.Database).sql"
    # if there is already a script there, we rename it
    if (Test-Path -PathType Leaf $OutputMigrationScript)
    {
      rename-item -literalpath $OutputMigrationScript -NewName "PreviousScript$(Get-Date -format FileDateTime)" -Force `
            -ErrorAction silentlycontinue -ErrorVariable +Errors;
    }
<# We assemble all the commandline arguments required for SQL Compare#>
    $AllArgs = @("/server1:$($OriginalClone.Netname)", # The source server
      "/database1:$($OriginalClone.Database)", #The name of the source database on the source server
      "/server2:$($ResetClone.Netname)", #the clone
      "/database2:$($ResetClone.Database)", #The name of the database on the clone server
      "/scriptfile:$OutputMigrationScript",
      "/include:Identical")
<# We add in extra parameters if necessary to deal with sql server authentication #>
    if ($OriginalClone.username -ne '')
    {
      $AllArgs += "/password1:$($OriginalClone.Credentials.GetNetworkCredential().Password)"
      $AllArgs += "/username1:$($OriginalClone.username)"
    }
    if ($ResetClone.username -ne '')
    {
      $AllArgs += "/password2:$($resetClone.Credentials.GetNetworkCredential().Password)"
      $AllArgs += "/username2:$($ResetClone.username)"
    }
<# now we can at last run SQL Compare to save the script changes just in case #>
    SQLCompare @AllArgs  > "$($data.WorkDirectory)\$($ResetClone.Database)-$($OriginalClone.Database).txt" #save the output
    if ($?) { "The clones have now been compared (see $($data.WorkDirectory)\$($ResetClone.Database)-$($OriginalClone.Database).txt)" }
    else
    {
      if ($LASTEXITCODE -eq 63) { 'Databases were identical' }
      else { $errors += "we had a comparison error! (code $LASTEXITCODE)" }
    }
  }
}
if ($ResetClone.AfterCreateScripts -ne $null -and $Errors.count -eq 0)
{
  $ConnectionString = "Data Source=$($ResetClone.Netname);Initial Catalog=$($ResetClone.Database)"
  if ($ResetClone.username -eq '')
  {
    $ConnectionString += ';Integrated Security=SSPI;'
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
  }
  
  else
  {
    $ConnectionString += ";uid=$($ResetClone.username);pwd=""$($Credentials.GetNetworkCredential().Password)"";"
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
  }
  $SqlConnection.Open()
  $sqlCommand = $sqlConnection.CreateCommand()
  
  $ResetClone.AfterCreateScripts.GetEnumerator() | foreach {
    $sqlCommand.CommandText = ([IO.File]::ReadAllText($_))
    $sqlCommand.ExecuteNonQuery()
    
  }
}

if ($Errors.count -eq 0)
{
  write-verbose "Reverting/resetting the clone $($ResetClone.Netname) $($ResetClone.Database)"
  $location = Get-SqlCloneSqlServerInstance | Where server -eq $ResetClone.Netname;
  if ($location -eq $null)
  { $errors += "could not find sql server corresponding with $($ResetClone.Netname) " }
  if ($Errors.count -eq 0)
  {
    Get-SqlClone -Name $ResetClone.Database.ToString() -Location $location `
           -ErrorAction silentlyContinue   `
           -ErrorVariable +Errors |
    Reset-SqlClone  `
             -ErrorAction silentlyContinue   `
             -ErrorVariable +Errors |
    Wait-SqlCloneOperation
    write-verbose "The clone $($ResetClone.Netname) $($ResetClone.Database) is now reset"
  }
  
}
<# We collect all the soft errors and deal with them here.#>
if ($errors.Count -gt 0)
{
  $errors | foreach {
    Write-error $_; "$((Get-Date).ToString()): $($_) the rollback was aborted">>"$($Data.WorkDirectory)\Errors.log";
    
    write-error("$($_)")
  }
};
