$database = 'MyDatabase' #the name of the database we are cloning e,g, AdventureWorks
$Data = @{
  "Database" = '$database';
  #where we have SQL Compare installed. Yours could be a different version
  "Original" = @{
  #We will clone from this database. This is the original, maybe a build stocked with data
    'Server' = 'MyUsefulServer'; #The SQL Server instance
    'Instance' = ''; #The SQL Server instance
    'Database' = "$($Database)"; #The name of the database
    'username' = 'PhilFactor'; #leave blank if windows authentication
    
  }
  "Image" = @{
    # this has the details of the image that each clone uses as its base
    #we use these details to create an image of what we built
    'Name' = "$($database)image"; #This is the name we want to call the image 
    #'Modifications' = @("$($env:USERPROFILE)\Clone\imageModificationScript.sql")
    'ServerURL' = 'http://MyCloneServer:14145'; #the HTTP address of the Clone Server
    'ImageDirectoryURL' = '\\MyFileStore\Clone'; #the URL of the image directory
    #'CloneTemplates' = @{
    #  'DatabaseProperties' = "$($env:USERPROFILE)\Clone\CloneModificationScript.sql"
    #}
      'Clone' = 
    @{
      "NetName" = "MyDevServer"; #the network name of the server
      "Database" = "$($database)Test"; #the name of the Database
      'username' = 'PhilFactor'; #leave this blank for windows security
    } #

                    
    }
}
$TheError = ''
Connect-SqlClone -ServerUrl $Data.Image.ServerURL # make a connectiuon to SQL Clone
<# If the image already exists, then use it, else create the image. If you need to
   change the original database, then delete the image before running the script #>
# first test to see if the image is there
$Image = Get-SqlCloneImage | where Name -eq $Data.Image.Name
if ($image -eq $null) # tut. No image
{
  $AllArgs = @{
    'Name' = $Data.Image.Name; #what is specified for its name in the data file
    'SqlServerInstance' = (Get-SqlCloneSqlServerInstance | Where server -eq $data.Original.Server);
    # we fetch the SqlServerInstanceResource for passing to the New-SqlCloneImage cmdlets.
    'DatabaseName' = "$($data.Original.Database)"; #the name of the database
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
  $ImageOperation = New-SqlCloneImage   `
                      @AllArgs -ErrorAction silentlyContinue -ErrorVariable +Errors   `
  # gets the ImageResource which then enables us to wait until the process is finished
  write-verbose "Creating the image called $(
      $Data.Image.Name) from $(
      $data.Original.Database) on $(
      $data.Original.Server)"
  Wait-SqlCloneOperation -Operation $ImageOperation
}
<# does the clone we want exist? #>
$clone = Get-SqlClone  `
   -ErrorAction silentlyContinue  `
   -Name "$($Data.Image.clone.Database)"  `
   -Location (Get-SqlCloneSqlServerInstance | 
                  Where server -ieq $Data.Image.clone.NetName)
<# If the clone does exist then zap it #>
if (($clone) -ne $null) #one already exists!
{
  write-warning  "Removing Clone $(
     $Data.Image.clone.Database) that already existed on $(
     $Data.Image.clone.NetName)"
  Remove-SqlClone $clone | Wait-SqlCloneOperation
}
<# Now Create the clone#>
$AllArgs = @{
  'Name' = $Data.Image.clone.Database;
  'Location' = (Get-SqlCloneSqlServerInstance | 
                     Where server -ieq $Data.Image.clone.NetName)
}
if ($Data.Image.clone.Modifications -ne $null)
{
  $AllArgs += @{ 'template' = (
                     Get-SqlCloneTemplate  `
                           -Image $data.image.Name   `
                           -Name $Data.Image.clone.Modifications) }
}

Get-SqlCloneImage -Name $data.Image.Name |
New-SqlClone @Allargs |
Wait-SqlCloneOperation
"Master, I have created your clone $(
  $Data.Image.clone.Database) on $($Data.Image.clone.NetName)" 
