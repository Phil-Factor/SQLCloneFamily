
$VerbosePreference = "Continue"
<# 
This powershell script removes an image, deleting all its clones first and backing up all
the changes to the metadata if you require it. It also checks the clone before deleting it
to make sure that there is no current activity */ It allows you to specify one or more
other SQL Scripts that you wish to use before a clone is deleted.
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
hierarchy. We iterate over the clones when making or updating them #>
$Errors = @()
#First we read in the configuration from a file (do it so we can use the ISE as well)
try {
    $Data = &"$executablePath\CloneConfig.ps1"
    }
catch
    {
    $Errors +="Could not access the config file at $executablePath\CloneConfig.ps1" 
    }

<# we read in the data as a structure. #>

<# now we need to find out the clone that we need to use to compare with the clone
that we want to revert to save any differences. #>
$originalClone = @()
$data.clones | foreach {
	if ($_.IsOriginal -eq $true)
	{ $originalClone = $_ };
}
<# check that we have got everything correctly #>
if ($originalClone.IsOriginal -ne $true)
{
	$errors += 'You have not defined which clone represents the original'
}

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
}
if ($data.tools.SQLCompare -ne $null)
<#we define the SQLCompare alias to make calling it easier. If the user hasn't defind the location of
the tool se simply don't do the comparison #>
{
	Set-Alias SQLCompare $data.tools.SQLCompare -Scope Script;
	$NoSQLCompare = $false
}
else
{ $NoSQLCompare = $true }

<# now we iterate through the clones other than the original one and if a SQL Compare is required we do it
we also check to make sure that none of the clones are being used. Finally we run any or all the scripts
specified to be run before the clone is destroyed. #>
if ($Errors.count -eq 0)
{
	$data.clones |
	Where {  (-not (($_.database -eq $originalClone.Database) -and ($_.NetName -eq $originalclone.NetName))) } |
	# don't do the original because it can't be written anyway.
    foreach {
        # we use this string so much it is worth calculating it just once
        $OurDB="$($_.Database) on $($_.NetName)"
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
            {  #because it isn't there
            write-verbose "The Clone $OurDB was not there";
            $CloneIsThere = $false }; 
            } 
        #We only do the compare if we can do, it is specified in the data, and if it is wanted for this clone
		if ($_.nocheck -ne $true -and $CloneIsThere -eq $true -and $NoSQLCompare -eq $false)
		{
			write-verbose "checking whether anything has changed on clone $OurDB compared with  $($OriginalClone.Netname) $($OriginalClone.Database)"
            <# we check to make sure that the path exists to the work directory#>
			if (-not (Test-Path -PathType Container "$($data.WorkDirectory)"))
			{ #if the path doesnt exist, we create it
				New-Item -ItemType Directory -Force -Path "$($data.WorkDirectory)" `
						 -ErrorAction silentlycontinue -ErrorVariable +Errors;
			}
            # we calculate the name of the file where to put the script that shows the changes 
			$OutputMigrationScript = "$($data.WorkDirectory)\$($_.Database)-$($OriginalClone.Database)"
			# if there is already a script file there, we rename it
			if (Test-Path -PathType Leaf "$OutputMigrationScript.sql")
			{
				rename-item -literalpath "$OutputMigrationScript.sql" -NewName "$OutputMigrationScript$(Get-Date -format FileDateTime).sql" -Force `
							-ErrorAction silentlycontinue -ErrorVariable +Errors;
			}
<# We assemble all the commandline arguments required for SQL Compare#>
			$AllArgs = @("/server1:$($OriginalClone.Netname)", # The source server
				"/database1:$($OriginalClone.Database)", #The name of the source database on the source server
				"/server2:$($_.Netname)", #the clone
				"/database2:$($_.Database)", #The name of the database on the clone server
				"/scriptfile:$($OutputMigrationScript).sql",
				"/include:Identical")
<# We add in extra parameters if necessary to deal with sql server authentication #>
			if ($OriginalClone.username -ne '')
			{
				$AllArgs += "/password1:$($OriginalClone.Credentials.GetNetworkCredential().Password)"
				$AllArgs += "/username1:$($OriginalClone.username)"
			}
			if ($_.username -ne '') # it must be SQL Server authentication
			{
				$AllArgs += "/password2:$($_.Credentials.GetNetworkCredential().Password)"
				$AllArgs += "/username2:$($_.username)"
			}
<# now we can at last run SQL Compare to save the script changes just in case #>
			SQLCompare @AllArgs  > "$($OutputMigrationScript).txt" #save the output
			if ($?) { "The clones have now been compared (see $($OutputMigrationScript).txt)" }
			else
			{
				if ($LASTEXITCODE -eq 63) { 'Databases were identical' }
				else { $errors += "we had a comparison error! (code $LASTEXITCODE)" }
			}
		}
<# now we  run any scripts necessary before deletion  as specified in the data file #>		
		if ($CloneIsThere -eq $true) #we only do it if the clone is still there
		{# we create a connection string to run some SQL
			$ConnectionString = "Data Source=$($_.Netname);Initial Catalog=$($_.Database);"
			if ($_.username -ieq '') #no user name. Windows authentication
			{
				$ConnectionString += ';Integrated Security=SSPI;'
			}
			else # we need to get that password. 
			{
				$ConnectionString += "uid=$($_.username);pwd=""$($_.Credentials.GetNetworkCredential().Password)"";"
			}
			$SqlConnection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
			# open a connection
			$SqlConnection.Open()
            # create a command
			$sqlCommand = $sqlConnection.CreateCommand()
            # Firstly, we do a query to see what activity there has been on this datebase recently
			$sqlCommand.CommandText = "USE master

            SELECT Coalesce(Min (DateDiff(MINUTE,last_read, GetDate())), 20000)
                     AS MinsSinceLastRead,
                   Coalesce(Min (DateDiff(MINUTE,last_write, GetDate())), 20000) 
                     AS MinsSinceLastwrite
	               FROM sys.dm_exec_connections A
                    INNER JOIN sys.dm_exec_sessions B ON
                        A.session_id = B.session_id
            WHERE database_id =Db_Id('$($_.Database)')"
			$reader=$sqlCommand.ExecuteReader()
            if ($reader.HasRows) #we read what data was returned.
                 {
                 while ($reader.Read())
                    {
                        $MinsSinceLastRead=$reader.GetInt32(0);
                        if ($MinsSinceLastRead -lt 30) 
                          {$errors+="A user read data only $MinsSinceLastRead minutes ago on $OurDB"}
                        $MinsSinceLastWrite=$reader.GetInt32(1);
                        if ($MinsSinceLastWrite -lt 30) 
                          {$errors+="A user wrote data only $MinsSinceLastWrite minutes ago on $OurDB"}
                    }
                 }
		    }
        <# now we execute any extra SQL Scripts specified by the data #>
		if ($_.BeforeDeleteScripts -ne $null)
		{
			$_.BeforeDeleteScripts.GetEnumerator() | foreach { # do each script
				$sqlCommand.CommandText = ([IO.File]::ReadAllText($_))
				$sqlCommand.ExecuteNonQuery()
			}
		}
	}
}
<# now we remove the clones and the image #>

If ($Errors.count -eq 0)
{<# now we very simply delete every clone  #>
	$image = Get-SqlCloneImage -Name $data.Image.Name
	#with the image object, we can now delete the clones
	Get-SqlClone -Image $image | foreach {
		write-verbose "Now deleting $($_.Name) on $((Get-SqlCloneSqlServerInstance | where Id -eq $_.LocationId).ServerAddress)"
		$_ | Remove-SqlClone | Wait-SqlCloneOperation
	};
	write-verbose "Now removing the image $($Image.Name) taken from $($Image.OriginServerName).$($Image.OriginDatabaseName) "
	$null = Remove-SqlCloneImage -Image $Image
};
<# We collect all the soft errors and deal with them here.#>
if ($errors.Count -gt 0)
{
	$errors | foreach {
		Write-error $_; "$((Get-Date).ToString()): $($_) the image deletion was aborted">>"$($Data.WorkDirectory)\Errors.log";
		
		write-error("$($_)")
	}
};
