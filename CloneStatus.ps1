$StatusDatabase = @{
  "NetName" = "MyServer"; #the network name of the server
  "Database" = 'NetworkData'; #the name of the Database
  'username' = 'Phil_Factor'; #leave this blank for windows security
  'StagingTableName' = 'RawStatusData';
}
$ObjectListPath = "$($env:Temp)\currentData.json"
$LogPath = "$($env:Temp)\CloneStatus.log"
function Get-ObjectCredentials ($TheHashTable)
{
  $pathToFile = "$env:USERPROFILE\$($TheHashTable.username)-$($TheHashTable.Netname).txt"
  #create a connection object to manage credentials
  $encryptedPasswordFile = $pathToFile
  # test to see if we know about the password un a secure string stored in the user area
  if (Test-Path -path $encryptedPasswordFile -PathType leaf)
  {
    #has already got this set for this login so fetch it
    $encrypted = Get-Content $encryptedPasswordFile | ConvertTo-SecureString
    $TheHashTable.Credentials = New-Object System.Management.Automation.PsCredential($TheHashTable.username, $encrypted)
  }
  else #then we have to ask the user for it
  {
    #hasn't got this set for this login
    $TheHashTable.Credentials = get-credential -Credential $TheHashTable.Username
    $TheHashTable.Credentials.Password | ConvertFrom-SecureString |
    Set-Content $pathToFile
  }
  
}
$JSONTable = ''
$popVerbosity = $VerbosePreference
$VerbosePreference = "Silentlycontinue"
# the import process is very noisy if you are in verbose mode
Import-Module sqlserver -DisableNameChecking #load the SQLPS functionality
$VerbosePreference = $popVerbosity
set-psdebug -strict
$ErrorActionPreference = "stop"

<# 
#>
# set "Option Explicit" to catch subtle errors
set-psdebug -strict
$ErrorActionPreference = "stop"

<# first, find out where we were executed from so we can be sure of getting the data#>
try
{ $executablepath = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition) }
catch
{
  $executablepath = "$(If ($psISE)
    { Split-Path -Path $psISE.CurrentFile.FullPath }
    Else { $global:PSScriptRoot })"
}
<# just to make it easier to understand, the various parameter values are structured in a 
hierarchy. We iterate over the clones#>
$Errors = @()
#First we read in the configuration from a file (do it so we can use the ISE as well)
try
{
  $Data = &"$executablePath\CloneConfig.ps1"
}
catch
{
  $Errors += "Could not access the config file at $executablePath\CloneConfig.ps1"
}

<# we read in the data as a structure. #>

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
$ImageDay = "$($image.createdDate.Day)-$($image.createdDate.Month)-$($image.createdDate.Year)"
$ObjectListPath = "$($env:Temp)\currentData$ImageDay.json"

# we need to get hold of the passwords for any connection that has a userid and attach it 
# to each clone object as a credential for use later.
# We save these credentials in a file within the user area, relying on NTFS security and 
# encryption (gulp)
# We only ask for the password once for each server. If you change the password
# you need to delete the corresponding file in your user area.
if ($Errors.count -eq 0)
{
  $data.clones | foreach {
    if ($_.username -ine '')
    {
      Get-ObjectCredentials($_)
    }
  }
}
Get-ObjectCredentials($StatusDatabase) # so we can write to it.


$Status = @()

<# now we iterate through the clones to fetch their status#>
if ($Errors.count -eq 0)
{
  $data.clones |
  foreach {
    $ThisClone = $_
    $OurDB = "$($ThisClone.Database) on $($ThisClone.NetName)"
    write-verbose "Checking  $OurDB"
    $CloneIsThere = $True; #assume yes until proven otherwise
    $sqlServerInstance = (Get-SqlCloneSqlServerInstance -ErrorAction SilentlyContinue |
      Where server -ieq $_.NetName); #test if it is there
    if ($sqlServerInstance -eq $null)
    {
      write-verbose "The Clone $OurDB was not found"; $CloneIsThere = $false
    }
    else
    {
      $clone = Get-SqlClone  `
                  -ErrorAction silentlyContinue  `
                  -Name "$($_.Database)"  `
                  -Location $sqlServerInstance
      if ($clone -eq $null)
      {
        #because it isn't there
        write-verbose "The Clone $OurDB was not there";
        $CloneIsThere = $false
      };
    }
    
    if ($CloneIsThere -eq $true) #we only do it if the clone is still there
    {
      # we create a connection string to run some SQL
      $ConnectionString = "Data Source=$($_.Netname);Initial Catalog=$($_.Database);"
      if ($_.username -ieq '') #no user name. Windows authentication
      {
        $ConnectionString += ';Integrated Security=SSPI;'
      }
      else # we need to get that password. 
      {
        $ConnectionString += "uid=$($_.username);pwd=""$($_.Credentials.GetNetworkCredential().Password)"";"
      }
      
      $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($connectionString) -ErrorAction SilentlyContinue
      # open a connection
      try
      { $SqlConnection.Open() }
      catch
      { $CloneIsThere = $false }
    }
    
    if ($CloneIsThere -eq $true) #we only continue if the clone can be connected to
    {
      # create a command
      $sqlCommand = $sqlConnection.CreateCommand()
      # Firstly, we do a query to see what activity there has been on this datebase recently
      $sqlCommand.CommandText = "USE master

            SELECT Coalesce(Min (DateDiff(MINUTE,last_read, GetDate())), 20000)
                     AS MinsSinceLastRead,
                   coalesce(max(last_read),'1/1/1900'),
                   Coalesce(Min (DateDiff(MINUTE,last_write, GetDate())), 20000) 
                     AS MinsSinceLastwrite,
                   coalesce(max(last_write),'1/1/1900')
                 FROM sys.dm_exec_connections A
                    INNER JOIN sys.dm_exec_sessions B ON
                        A.session_id = B.session_id
            WHERE database_id =Db_Id('$($_.Database)')"
      $reader = $sqlCommand.ExecuteReader()
      if ($reader.HasRows) #we read what data was returned.
      {
        while ($reader.Read())
        {
          $MinsSinceLastRead = $reader.GetInt32(0);
          $LastRead = $reader.GetDateTime(1);
          $MinsSinceLastWrite = $reader.GetInt32(2);
          $LastWrite = $reader.GetDateTime(3);
        }
      }
      $reader.Close()
      #if the object list is there.
      if ($_.IsOriginal -ne 0)
      {
        #is the file there?
        if (-not [System.IO.File]::Exists($ObjectListPath))
        {
          $sqlCommand.CommandText = "
                     USE $($_.Database)
                     Declare @JsonString Nvarchar(max)=(SELECT [Object_ID], Modify_Date FROM $($_.Database).sys.objects
                     WHERE is_ms_shipped =0 FOR JSON AUTO)
                     Select @JsonString
                     "
          $JSONTable = ''
          $reader = $sqlCommand.ExecuteReader()
          if ($reader.HasRows) #we read what data was returned.
          {
            while ($reader.Read())
            {
              $JSONTable += $reader.GetString(0)
              
            }
          }
          $JSONTable>$ObjectListPath
          $reader.Close()
        }
      }
      
      $sqlCommand = $sqlConnection.CreateCommand()
      $sqlCommand.CommandText = "
            use $($_.Database)
            SELECT count(*)
            FROM sys.objects new
             LEFT OUTER join
            OpenJson(@json)
            WITH (  
            [Object_ID] INT,
              Modify_Date Datetime
          ) AS original
             ON original.object_id=new.Object_Id AND original.modify_date= new.modify_date
             WHERE new.is_ms_shipped =0 and original.object_id IS NULL"
      $param1 = $sqlCommand.Parameters.Add("@JSON", [System.Data.SqlDbType]::NVarChar)
      if ($JSONTable -eq '')
      { $JSONTable = [IO.File]::ReadAllText($ObjectListPath) }
      $param1.Value = $JSONTable
      $Changes = $sqlCommand.ExecuteScalar()
      
      
      $ThisCloneStatus = $clone |
      Select State, CreatedBy, Name, SizeInBytes, TemplateName,
           @{ Name = "CreatedDate"; Expression = { $_.CreatedDate.DateTime } },
           @{ Name = "MinsSinceLastRead"; Expression = { [int]$MinsSinceLastRead.ToInt32($Null) } },
           @{ Name = "LastRead"; Expression = { $LastRead.DateTime } },
           @{ Name = "MinsSinceLastWrite"; Expression = { [int]$MinsSinceLastWrite.ToInt32($Null) } },
           @{ Name = "Changes"; Expression = { [int]$Changes.ToInt32($Null) } },
           @{ Name = "LastWrite"; Expression = { $LastWrite.DateTime } },
           @{ Name = "ImageName"; Expression = { $image.Name } },
           @{ Name = "ImageCreatedBy"; Expression = { $image.CreatedBy } },
           @{ Name = "ImageCreatedDate"; Expression = { $image.CreatedDate.DateTime } },
           @{ Name = "ImageState"; Expression = { $image.State.value__.ToInt32($Null) } },
           @{ Name = "ImageSizeInBytes"; Expression = { $image.SizeInBytes.ToInt32($Null) } },
           @{ Name = "Instance"; Expression = { $ThisClone.NetName } },
           @{ Name = "OriginDatabaseName"; Expression = { $image.OriginDatabaseName } },
           @{ Name = "OriginServerName"; Expression = { $image.OriginServerName } }
      $status += $ThisCloneStatus
    }
    else
    {
      $status += @{
        'State' = 0;
        'Name' = $ThisClone.Database;
        'instance' = $ThisClone.NetName;
        'ImageName' = $image.Name;
        'ImageCreatedBy' = $image.CreatedBy;
        'ImageCreatedDate' = $image.CreatedDate.DateTime;
        'ImageState' = $image.State.value__.ToInt32($Null);
        'ImageSizeInBytes' = $image.SizeInBytes.ToInt32($Null);
        'OriginDatabaseName' = $image.OriginDatabaseName;
        'OriginServerName' = $image.OriginServerName;
      }
    }
  }
}
<# Now we have gathered all the information we need, we can now wrap it into a JSON document and sent it to the reporting database #>

<# First we make sure we have credentials #>
$json = $status | ConvertTo-JSON
$ConnectionString = "Data Source=$($StatusDatabase.NetName);Initial Catalog=$($StatusDatabase.Database);"
if ($StatusDatabase.username -ieq '') #no user name. Windows authentication
{
  $ConnectionString += ';Integrated Security=SSPI;'
}
else # we need to get that password. 
{
  $ConnectionString += "uid=$($StatusDatabase.username);pwd=""$($StatusDatabase.Credentials.GetNetworkCredential().Password)"";"
}
$SqlConnection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
# open a connection
$SqlConnection.Open()
# create a command
$sqlCommand = $sqlConnection.CreateCommand()
$sqlCommand.CommandText = "Insert into $($StatusDatabase.StagingTableName)(collectionDate,Status,Collector) Select GetDate(),@json,@Collector"
$param1 = $sqlCommand.Parameters.Add("@JSON", [System.Data.SqlDbType]::NVarChar)
$param1.Value = $json
$param2 = $sqlCommand.Parameters.Add("@Collector", [System.Data.SqlDbType]::NVarChar)
$param2.Value = $data.Image.Name
try
{
  $sqlCommand.ExecuteScalar()
}
catch [System.Exception]
{
  $Errors += $_.Exception.InnerException.Errors
}
if ($Errors.count -gt 0) #if we couldn't import something
{
  $Errors | foreach{
    write-warning "$(Get-Date):Error: '$($_)'"
    $_>>$logpath
  }
}
else
{ "$(Get-Date): Successfully checked the clone status">>$logpath }
