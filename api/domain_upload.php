<?
	include_once 'function.php';
	
	echo '2003';
		
	if ($auth == '1001')
	{
		$port = preg($_POST['port'], "[^0-9]");
		if ($port < 1 || $port > 65536)
		{
			die("Error: Port number must be between 1 and 65536.<end>");
		}
		
		
		$d = preg($_POST['d']);
		$temp = getDomainInfo($d);
		
		if ($temp[0] > 0)
		{
			if ($user['id'] == $temp[1])
			{
				$code = eEscape($_POST['filedata']);
				mysql_query("INSERT INTO domainscripts VALUES ($temp[0], $port, '$code', '".$_SERVER['REMOTE_ADDR']."', ".time().") ON DUPLICATE KEY UPDATE code='$code', ip='".$_SERVER['REMOTE_ADDR']."', time=".time().";");
			
				if (mysql_error())
				{
					die('fail<end>');
				}
				else
				{
					die('success<end>');
				}
			}
			else
			{
				die('Restricted access.<end>');
			}
		}
		else
		{
			die('Domain does not exist.<end>');
		}
	}
	else
	{
		die('Access denied.<end>');
	}
	/*
	
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
			$result = mysql_query("UPDATE domain_scripts SET script='$filedata' where domain='$d' and port='$port'");
		}else{
			//add it as new
		
			$ctime = addslashes(date('h:i A'));$ctime=str_replace("zz0","","zz".$ctime);$ctime=str_replace("zz","",$ctime);$ctime=addslashes($ctime);
			$cdate =trim( str_replace(" 0"," "," ".date('dS \of F Y')));
			$ahostname = gethostbyaddr($_SERVER['REMOTE_ADDR']);
			$aip = $_SERVER['REMOTE_ADDR'];
			$result = mysql_query("INSERT INTO domain_scripts (domain, port, script, accesslog, createdate, createtime, ip, hostname) VALUES('$d','$port','$filedata','Created at $ctime on $cdate<br>','$cdate','$ctime','$aip','$ahostname' ) ") or die(mysql_error());  
		}

			
			die("File upload complete: ".strtoupper($originaldomain).":$port<end>");
	
	}else{
	
		//domain not found
		die("Server Not Found: ".strtoupper($originaldomain)."<end>");
	}

}else{

	echo "Access Denied 65233";
}


echo "<end>";



*/
?>