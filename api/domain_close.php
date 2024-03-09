<?php
	include_once "function.php";

	$returnwith = preg($_GET['returnwith'], "[^0-9]");
	
	// If user is this dumb.. then.. you know..
	// $d = str_replace("http://", "", str_replace("www.","",trim($d)));



if (trim($returnwith)==""){$returnwith="2000";}
echo $returnwith;




$port=trim($port);
if ($port < 1 || $port > 65536){die("Error: Port number must be between 1 and 65536.<end>"); }





if (auth()=="1001"){
	
	//----------------------------------------------------------------------------------------------------------
	//NOTE - when modifying this script, consider that you may need to modify domain_download.php as well!!!
	//----------------------------------------------------------------------------------------------------------
	
	$originaldomain=trim($d);
	$d=getdomain($d); //make sure its a domain name so mysql can identify it


	mysql_connect("localhost", $mysql_username, $mysql_password); mysql_select_db($mysql_database);
	$result=mysql_query("SELECT ind from domains where domain='$d' and owner='$u'")or die(mysql_error());  
	
	
	if (strtolower($u)=="admin"){}else{
		//only ADMIN can download from anyone's domain name!
		if (mysql_num_rows($result)==1){}else{
		
			//check subowners
			$result2=mysql_query("SELECT subowners from domains where domain='$d'");
				while($row = mysql_fetch_array( $result2 )) {
					$subowners = strtolower($row['subowners']);
				}
				
			if(strstr($subowners,":".trim(strtolower($u)).":")){
				//subowner found, continue!
			}else{		
				die("Error: $d [user denied]newlineMake sure this domain name is registered to you.<end>");
			}
			
			
		}
	}
	
	//----------------------------------------------------------------------------------------------------------
	//NOTE - when modifying this script, consider that you may need to modify domain_download.php as well!!!
	//----------------------------------------------------------------------------------------------------------
	

	//is it a domain?
	if (domain_exists($d)){
		if (mysql_num_rows(mysql_query("SELECT port from domain_scripts where domain='$d' and port='$port'"))>0){
			//is there already a script on this port? replace it
			$result = mysql_query("DELETE FROM domain_scripts WHERE domain='$d' and port='$port'");
			//$result = mysql_query("UPDATE domain_scripts SET script='$filedata' where domain='$d' and port='$port'");
		}else{
			//no script exists.
			die("No script is active on this port.<end>");
		}

			
			die("Port successfully closed.: ".strtoupper($originaldomain).":$port<end>");
	
	}else{
	
		//domain not found
		die("Server Not Found: ".strtoupper($originaldomain)."<end>");
	}

}else{

	echo "Access Denied 65233";
}


echo "<end>";




?>