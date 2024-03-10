<?php
	include_once "function.php";
	include_once('mysql_config.php');
	global $db;

	$returnwith = (string)(int)$_GET['returnwith'];
	
	// If user is this dumb.. then.. you know..
	// $d = str_replace("http://", "", str_replace("www.","",trim($d)));



if (trim($returnwith)=="0"){$returnwith="2000";}
echo $returnwith;




$port=(int)$port;
if ($port < 1 || $port > 65536){die("Error: Port number must be between 1 and 65536.<end>"); }





if ($auth=="1001"){
	
	//----------------------------------------------------------------------------------------------------------
	//NOTE - when modifying this script, consider that you may need to modify domain_download.php as well!!!
	//----------------------------------------------------------------------------------------------------------
	
	$originaldomain=trim($d);
	$d=getdomain($d); //make sure its a domain name so mysql can identify it

	$result=$db->query("SELECT id from domains where domain='$d' and owner='$u'")or die($db->error);  
	
	
	if (strtolower($u)=="admin"){}else{
		//only ADMIN can download from anyone's domain name!
		if ($db->num_rows($result)==1){}else{
		
			//check subowners
			$result2=$db->query("SELECT subowners from domains where domain='$d'");
				while($row = $db->fetch_array( $result2 )) {
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
		if ($db->num_rows($db->query("SELECT port from domain_scripts where domain='$d' and port='$port'"))>0){
			//is there already a script on this port? replace it
			$result = $db->query("DELETE FROM domain_scripts WHERE domain='$d' and port='$port'");
			//$result = $db->query("UPDATE domain_scripts SET script='$filedata' where domain='$d' and port='$port'");
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