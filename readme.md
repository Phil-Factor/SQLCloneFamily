This is the code that covers a series of articles that explains a collection of PowerShell scripts that use a shared data file.

So far, we have 
* Deploying and Reverting Clones for Database Development and Testing
* Making changes to Images and Clones for Database Development and Testing
* Safely Deleting and updating Clones for Database Development and Testing 

The Data file maps out a Clone installation consisting of a source database, an image and some clones. 

The scripts show how to show how to install a grop of clones from an image. It shows how to roll back a clone to its original state, and to delete all the clones. 

By combining the deletion script with the install script, you can, in effect, update the clones when the original database changes. 

The scripts allow you to use Image templates to alter the image before the clones are taken from it, and both Clone templates and SQL Scripts to check and alter the individual clones. The scripts aim to manage the rollback and deletion process to ensure that work doesn’t get lost and clones can be, effectively, updated without hassle..

When you are using SQL Clone for development work, it isn’t always entirely practical to update clones to a new database version via a migration script. You can certainly apply a synchronization script in order to bring them up to the same version, but you will gradually lose the great advantage of Clone, the huge saving in disk space, because the changes will be held on a difference disk on local storage on the server.  Also, you would be solving a problem that has ceased to exist, which is the length of time it takes to copy a database. With clone, it is a matter of seconds.

It is much better, once a new build has been successfully made and successfully tested, to delete all the clones and then the image that they used. Once that is done, then you can create the new image from the successful build with the same name and create the new clones under their previous names.  As a refinement of this, with a large development or test database, you can create the new image first under a different name before dropping the old clones and re-creating them with the new image before dropping the old image.


Please note that it is very easy to do most of what I in the SQL Clone GUI, and you can do it all if you add the use of SSMS. If you merely want simple PowerShell example scripts, then look at the recent documentation that has several examples.  

These scripts are used where your requirement is for a regular process that is capable of automating  more complex provisioning tasks 

The scripts in this series are unusual in that you get it to do different thing, or manage different clones or images by changing the data rather than using different parameters to a function. The script references a shared data structure. If you want a change to a clone by applying a series of scripts, you merely list them in the data: you shouldn’t need to touch the code.  You change the location of clones or the number of clones just by changing the structure. For production work, this means that you require few if any code changes, just change the data. 


