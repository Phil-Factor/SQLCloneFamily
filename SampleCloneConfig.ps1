$database = 'MyDatabase' #the name of the database we are cloning e,g, AdventureWorks
@{
  "Database" = '$database';
  "WorkDirectory" = "$($env:USERPROFILE)\Clone"; #a directory for placing scripts, logs etc
  "tools" = @{ 'SQLCompare' = 'C:\Program Files (x86)\Red Gate\SQL Compare 13\SQLCompare.exe' }
  #where we have SQL Compare installed. Yours could be a different version
  #Leave this blank if you don't want clones to be checked before you kill them
  "Origin" = @{
    #We will clone from this database. This is the IsOriginal, maybe a build stocked with data
    'Server' = 'BuildServer'; #The SQL Server instance
    'Instance' = 'Our2017'; #The SQL Server instance
    'Database' = "$($Database)"; #The name of the database
    'username' = '' #leave blank if windows authentication
  }
  "Image" = @{
    # this has the details of the image that each clone uses as its base
    #we use these details to create an image of what we built
    'Name' = "$($database)image"; #This is the name we want to call the image 
    'Modifications' = @("$($env:USERPROFILE)\Clone\imageModificationScript.sql")
    'ServerURL' = 'http://MyCloneServer:14145'; #the HTTP address of the Clone Server
    'ImageDirectoryURL' = '\\MyFileServer\Clone' #the URL of the image directory
    'CloneTemplates' = @{
      'DatabaseProperties' = "$($env:USERPROFILE)\Clone\CloneModificationScript.sql"
    }
  }
<# here is where we put the list of clones. 
You can specify as many as you wish and they'll all be created #>
  "Clones" = @(
    @{
      "NetName" = "MyFirstServer"; #the network name of the server
      "Database" = "$($database)IsOriginal"; #the name of the Database
      'username' = ''; #leave this blank for windows security
      'IsOriginal' = $true;
    }, #is this the IsOriginal (only one should be 'true'
    @{
      "NetName" = "MySecondServer"; #the network name of the server
      "Database" = "$($database)Yan"; #the name of the Database
      'username' = 'PhilFactor'; #leave this blank for windows security
      'IsOriginal' = $false;
      'CloneTemplate' = 'DatabaseProperties'; #the name of the template to run
      "AfterCreateScripts" = @("$($env:USERPROFILE)\Clone\ServerModificationScript.sql")
    } #is this the IsOriginal
    @{
      "NetName" = "MyThirdServer"; #the network name of the server
      "Database" = "$($database)Tan"; #the name of the Database
      'username' = 'TonyDavis'; #leave this blank for windows security
      'IsOriginal' = $false;
      'NoCheck' = $True; #do you want this to be checked against SQL Compare
    } #is this the IsOriginal
    @{
      "NetName" = "MyFourthServer"; #the network name of the server
      "Database" = "$($database)Tethera"; #the name of the Database
      'username' = 'AuntiKathi'; #leave this blank for windows security
      'IsOriginal' = $false;
    } #is this the IsOriginal
  )
}