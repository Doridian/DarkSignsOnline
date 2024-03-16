<?php

include_once 'function.php';
global $auth;


$u=trim($u);
$uid = $auth_data['id'];
$returnwith=trim($returnwith);
$d=str_replace("http://","",str_replace("www.","",trim($_REQUEST['d'])));

$filename = $_REQUEST['filename'];


if (trim($returnwith)==""){$returnwith="2000";}
echo $returnwith;




$port=(int)$_REQUEST['port'];
if ($port < 1 || $port > 65536){die("Error: Port number must be between 1 and 65536."); }





if ($auth=="1001"){
	
	//----------------------------------------------------------------------------------------------------------
	//NOTE - when modifying this script, consider that you may need to modify domain_download.php as well!!!
	//----------------------------------------------------------------------------------------------------------

	$originaldomain=trim($d);
	$dInfo = getDomainInfo($d); //make sure its a domain name so mysql can identify it
	$subowners = strtolower($dInfo['subowners']);

	if ($dInfo[1] !== $uid && !strstr($subowners,":".trim(strtolower($u)).":")) {
		die("Error: $d [user denied]newlineMake sure this domain name is registered to you.");
	}
	
	//----------------------------------------------------------------------------------------------------------
	//NOTE - when modifying this script, consider that you may need to modify domain_download.php as well!!!
	//----------------------------------------------------------------------------------------------------------

	$dId = $dInfo[0];
	$result=$db->query("SELECT code from domainscripts where domain_id='$dId' and port=$port");
	if ($result->num_rows > 0) {
		//grab the file to download!
		while($row = $result->fetch_array()) { $script = $row['code']; }

		$script=str_replace("\n","*- -*",$script);
		$script=str_replace("\r","",$script);
		die("$filename:$script");			
	}else{
		die("No Script Found: ".strtoupper($originaldomain).":$port");
	}

}else{

	echo "Access Denied";
}
