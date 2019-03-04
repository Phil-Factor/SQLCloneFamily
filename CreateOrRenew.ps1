
<# Before running this, you need to make a list of all the clones you want, and choose
which one will be the reference database. This is done in a config file that will 
also need to have the various dtails of where the image is to be stored and where
the Clone server is. You need to tell it the name of the database, the 
directory where you want to store the log files and scripts an so on. This is in
a data file called CloneConfig.ps1. A sample version is provided.

You need to have set SQL Clone up properly so it is in working order.    #>
<# first, find out where we were executed from each environment has a different way
of doing it. It all depends how you execute it#>
try
{ $executablepath = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition) }
catch
{
  $executablepath = "$(If ($psISE)
    { Split-Path -Path $psISE.CurrentFile.FullPath }
    Else { $global:PSScriptRoot })"
}

$VerbosePreference = "Continue"
set-psdebug -strict
$ErrorActionPreference = "stop"
#First we read in the configuration from a file (do it so we can use the ISE as well)
$Data = &"$executablepath\CloneConfig.ps1"
<# we read in the data as a structure. #>
$Errors = @()
<#Then we do some sanity checking to make sure that the data is reasonably viable.
We apply defaults if possible The parameter verification is OTT at the moment 
but my scripts tend to grow ...#>

# the fourth value means -1 provide a blank default, 0 = not a directory-must be there, 
# 1=create if not exist, 2 = must already exist
@(($data.WorkDirectory, 'WorkDirectory', '', 1),
  ($data.Origin.username, 'Origin', 'username', 0),
  ($data.Origin.instance, 'Origin', 'instance', 0),
  ($data.Origin.Server, 'Origin', 'Server', 0),
  ($data.Image.Name, 'Image', 'Name', 0),
  ($data.Image.ImageDirectoryURL, 'Image', 'ImageDirectoryURL', 0),
  ($data.Image.ServerURL, 'Image', 'ServerURL', 0)
) | foreach{
  if ($_[0] -eq $null) #if the parameter has'nt been provided
  {
    # we give a default '' else flag up an error
    if ($_[3] -eq -1) { $data.$_[1].$_[2] = '' } #should be blank
    else
    { $Errors += "There is no $($_[1]).$($_[2]) defined" }
  }
  elseif ($_[3] -ge 1) #it is a directory that needs to be tested
  {
    if (-not (Test-Path -PathType Container $_[0]))
    {
      if ($_[3] -eq 2)
      {
        New-Item -ItemType Directory -Force -Path $_[0] `
             -ErrorAction silentlycontinue -ErrorVariable +Errors;
      }
      else { $Errors += "the path '$($_[0])'in $($_[1]).$($_[2])  does not exist" }
    }
  }
}

if ($Errors.count -eq 0) # if we have soft errors fall out through the application
{
  $CloneImageName = "$($data.Image.Name)"
  #Initiates a connection with a SQL Clone Server.
  #If no credential is specified then the current user's credentials will be used.
  Connect-SQLClone -ServerUrl $data.Image.ServerURL   `
           -ErrorAction silentlyContinue   `
           -ErrorVariable +Errors
  $CloneExists = Get-SqlCloneImage -Name $CloneImageName -ErrorAction silentlyContinue
  if ($CloneExists -ne $null) #does an image with this name already exist?
  { Throw " Image named $($CloneExists.Name) already exists. Delete it or chose another name" }
  write-verbose "Connecting to $($data.Image.ServerURL) Clone Server to create the image called $CloneImageName"
  #we specify the source of the image, which must have an agent and be known to the Clone Server
}
if ($Errors.count -eq 0) # if we have soft errors drop out through the application
{
  $AllArgs = @{
    'Name' = $CloneImageName; #what is specified for its name in the data file
    'SqlServerInstance' = (Get-SqlCloneSqlServerInstance | Where server -eq $data.Origin.Server);
    # we fetch the SqlServerInstanceResource for passing to the New-SqlCloneImage cmdlets.
    'DatabaseName' = "$($data.Origin.Database)"; #the name of the database
    'Destination' = (Get-SqlCloneImageLocation |
      Where Path -eq $data.Image.ImageDirectoryURL) #where the image is stored
  }
  if ($Data.Image.Modifications -ne $null)
  {
    $ImageChangeScript = @();
    $Data.Image.Modifications.GetEnumerator() | foreach{
      $ImageChangeScript += New-SqlCloneSqlScript -Path $_
    }
    $AllArgs += @{ 'Modifications' = $ImageChangeScript }
  }
  
  # Starts creating a new image from either a live database or backup.
  $ImageOperation = New-SqlCloneImage @AllArgs -ErrorAction silentlyContinue -ErrorVariable +Errors   `
                    # gets the ImageResource which then enables us to wait until the process is finished
  write-verbose "Creating the image called $CloneImageName from $($data.Origin.Database) on $($data.Origin.Server)"
  Wait-SqlCloneOperation -Operation $ImageOperation
  
  
}
if ($Errors.count -eq 0) # if we have soft errors spin out through the application
{
  # check that we have a valid clone image
  $ourCloneImage = Get-SqlCloneImage  `
                     -Name $CloneImageName  `
                     -ErrorAction SilentlyContinue -ErrorVariable +Errors
  if ($ourCloneImage -eq $null)
  {
    $Errors += "couldn't find the clone $CloneImageName That has just been created"
  }
  if ($ourCloneImage.State -ne 'Created')
  { $Errors += "We hit a problem with the image. It's state is $($ourCloneImage.State)" }
}
if ($data.Image.CloneTemplates -ne $null -and $Errors.count -eq 0)
{
  $data.Image.CloneTemplates.GetEnumerator() | foreach{
    $SqlCloneTemplate = New-SqlCloneTemplate   `
                         -Name $_.Name   `
                         -Image $ourCloneImage   `
                         -Modifications (New-SqlCloneSqlScript -Path $_.Value)   `
                         -ErrorAction SilentlyContinue -ErrorVariable +Errors
  }
}
#clone it as whatever database is specified to whatever sql server clone hosts are specified

if ($Errors.Count -eq 0) # if we have soft errors tumble out through the application
{
  # we now just iterate through our list of clones to create each one
  $data.clones | foreach {
    $clone = $null; $Thedatabase = $_.Database;
    #get the correct instance that has an agent installed on it.
    $sqlServerInstance = (Get-SqlCloneSqlServerInstance | Where server -ieq $_.NetName);
    if ($sqlServerInstance -eq $null) { Throw "Unable to find the clone agent for $($_.NetName)" }
    write-verbose "Cloning $($_.Database) on $($_.NetName)"
    #see if there is a pre-existing clone
    $clone = Get-SqlClone  `
                -ErrorAction silentlyContinue  `
                -Name "$($TheDatabase)"  `
                -Location $sqlServerInstance
    if (($clone) -ne $null) #one already exists!
    {
      write-warning  "Removing Clone $Thedatabase that already existed on $($_.NetName)"
      Remove-SqlClone $clone | Wait-SqlCloneOperation
    }
    $AllArgs = @{
      'Name' = "$($Thedatabase)";
      'Location' = $SqlServerInstance;
    }
    if ($_.CloneTemplate -ne $null)
    {
      $AllArgs += @{ 'template' = (Get-SqlCloneTemplate -Image $ourCloneImage -Name $_.CloneTemplate) }
    }
    
    Get-SqlCloneImage -Name $data.Image.Name |
    New-SqlClone @Allargs |
    Wait-SqlCloneOperation
    write-verbose "cloned $($_.Database) on $($_.NetName)"
    if ($errors.Count -gt 0)
    {
      continue
    }
        <# we need to make the IsOriginal database RO #>
    if ($_.IsOriginal -eq $true -or $_.AfterCreateScripts -ne $null)
    {
      $ConnectionString = "Data Source=$($_.Netname);Initial Catalog=$Thedatabase;"
      if ($_.username -ieq '')
      {
        $ConnectionString += ';Integrated Security=SSPI;'
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
      }
      else
      {
        #create a connection object to manage credentials
        $encryptedPasswordFile = "$env:USERPROFILE\$($_.username)-$($_.Netname).txt"
        # test to see if we know about the password un a secure string stored in the user area
        if (Test-Path -path $encryptedPasswordFile -PathType leaf)
        {
          #has already got this set for this login so fetch it
          $encrypted = Get-Content $encryptedPasswordFile | ConvertTo-SecureString
          $Credentials = New-Object System.Management.Automation.PsCredential($_.username, $encrypted)
        }
        else #then we have to ask the user for it once and once only
        {
          #hasn't got this set for this login
          $Credentials = get-credential -Credential $Username
          $Credentials.Password | ConvertFrom-SecureString |
          Set-Content "$env:USERPROFILE\$SourceLogin-$SourceServerName.txt"
        }
        $ConnectionString += "uid=$($_.username);pwd=""$($Credentials.GetNetworkCredential().Password)"";"
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
      }
      $SqlConnection.Open()
      $sqlCommand = $sqlConnection.CreateCommand()
      if ($_.IsOriginal -eq $true)
      {
        $sqlCommand.CommandText = "USE [master] ALTER DATABASE [$Thedatabase] SET READ_ONLY WITH NO_WAIT"
        $sqlCommand.ExecuteNonQuery()
      }
      if ($_.AfterCreateScripts -ne $null)
      {
        $_.AfterCreateScripts.GetEnumerator() | foreach {
          $sqlCommand.CommandText = ([IO.File]::ReadAllText($_))
          $sqlCommand.ExecuteNonQuery()
        }
      }
    }
  }
}
# do all the error reporting in one place
if ($errors.Count -gt 0)
{
  $errors | foreach {
    Write-error $_; "$((Get-Date).ToString()): $($_) the clone-creation was aborted">>"$Data.WorkDirectory\Errors.log";
    
    write-error("$($_)")
  }
};

