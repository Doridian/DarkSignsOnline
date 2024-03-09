<?
	include_once 'function.php';

	echo '4100';

	if ($auth == '1001')
	{
		
		
		$port = (int)$_REQUEST['port'];

		if ($port < 1 || $port > 65536)
		{
			die('not found<end>');
		}
		$d = $db->real_escape_string($_REQUEST['d'], '[^a-zA-Z0-9.-]');
		$d = strtolower($d); 
		
		$temp = getDomainInfo($d);

		if ($temp[0] > 0)
		{
			$exists = $db->query("SELECT code FROM domainscripts WHERE domain_id='$temp[0]' AND port='$port'");
			if ($db->num_rows($exists) == 1)
			{
				$code = $db->fetch_row($exists);
				echo $d.'_'.$port.'::'.$code[0];
			}
			else
			{
				//die('Domain does not have a script on that port.');
				echo 'not found';
			}
		}
		else
		{
			//die('Domain does not exist.<end>');
			echo 'not found';
		}

		/*
	
		$d = getdomain($_GET['d']); //make sure its a domain name so mysql can identify it
		echo $d;

		//is it a domain?
		if (domain_exists($d))
		{

	
		$result = $db->query("SELECT * from domain_scripts where domain='$d' and port='$port'");

		if ($db->num_rows($result)==1){
		//found, send the script!

		while($row = $db->fetch_array( $result )) {
		$script = trim($row['script']);
		}


		$script = str_replace("\n         ","\n",$script); //remove more spaces in case they exist
		$script = str_replace("\n        ","\n",$script);
		$script = str_replace("\n       ","\n",$script);
		$script = str_replace("\n      ","\n",$script);
		$script = str_replace("\n     ","\n",$script);
		$script = str_replace("\n    ","\n",$script);
		$script = str_replace("\n   ","\n",$script);
		$script = str_replace("\n  ","\n",$script);
		$script = str_replace("\n ","\n",$script);
		$script = str_replace("\n^         ","\n",$script); //remove more spaces in case they exist
		$script = str_replace("\n^        ","\n",$script);
		$script = str_replace("\n^       ","\n",$script);
		$script = str_replace("\n^      ","\n",$script);
		$script = str_replace("\n^     ","\n",$script);
		$script = str_replace("\n^    ","\n",$script);
		$script = str_replace("\n^   ","\n",$script);
		$script = str_replace("\n^  ","\n",$script);
		$script = str_replace("\n^ ","\n",$script);

		$script = str_replace("\n\t\t\t\t","\n",$script); //remove tabs in case they exist
		$script = str_replace("\n\t\t\t","\n",$script);
		$script = str_replace("\n\t\t","\n",$script);
		$script = str_replace("\n\t","\n",$script);
		$script = str_replace("\n^\t\t\t\t","\n",$script); //remove tabs in case they exist
		$script = str_replace("\n^\t\t\t","\n",$script);
		$script = str_replace("\n^\t\t","\n",$script);
		$script = str_replace("\n^\t","\n",$script);

		$script = str_replace("\n      ","\n",$script); //remove more spaces in case they exist
		$script = str_replace("\n     ","\n",$script);
		$script = str_replace("\n    ","\n",$script);
		$script = str_replace("\n   ","\n",$script);
		$script = str_replace("\n  ","\n",$script);
		$script = str_replace("\n ","\n",$script);
		$script = str_replace("\n^      ","\n",$script); //remove more spaces in case they exist
		$script = str_replace("\n^     ","\n",$script);
		$script = str_replace("\n^    ","\n",$script);
		$script = str_replace("\n^   ","\n",$script);
		$script = str_replace("\n^  ","\n",$script);
		$script = str_replace("\n^ ","\n",$script);


		//replace filekeys for server commands
		//$script = str_ireplace("\nSeRvER ","\nSERVER ".filekey($d).":---:".trim($d).":----:","r676723\n".$script);
		//$script = str_replace("r676723\n","",$script);
		//$script = str_ireplace("fileserver(","fileserver(".filekey($d).", ".trim($d).", ",$script);				

		//--------------------------------------------------------------------------------
		//loop through the entire file and check for lines that should be encrypted
		if(strstr("\n".strtolower(str_replace(" ","",str_replace("\t","",$script))),"\n^all")){
		//encode the entire file
		$encodeall=1;
		}else{
		$encodeall=0;
		}

		$script=str_replace("\r","\n",$script);
		$script=str_replace("*- -*","\n",$script);
		$script=str_replace("\n\n","\n",$script);
		$sarray=explode("\n",$script);
		$alls="";

		for ($x=0; $x < count($sarray);$x++){			
		$tmps=trim($sarray[$x]);


		if(strstr("-%-".strtolower($tmps),"-%-server ")){
		$tmps = str_ireplace("-%-SeRvER ","SERVER ".filekey($d,$tmps).":---:".trim($d).":----:","-%-".$tmps);
		$tmps = str_replace("-%-","",$tmps);
		}
		if(strstr("-%-".strtolower($tmps),"-%-^server ")){
		$tmps = str_ireplace("-%-^SeRvER ","^SERVER ".filekey($d,$tmps).":---:".trim($d).":----:","-%-".$tmps);
		$tmps = str_replace("-%-","",$tmps);
		}


		if(strstr(strtolower($tmps),"fileserver(")){
		$tmps = str_ireplace("fileserver(","fileserver(".filekey($d,$tmps).", ".trim($d).", ",$tmps);				
		}


		if($encodeall==0){
		if (substr($tmps,0,1)=="^"){
		$tmps="^".dsoencode(substr($tmps,1,9999));
		}
		}else{
		//encode the entire file!
		if (substr($tmps,0,1)=="^"){	$tmps=substr($tmps,1,9999);		}
		$tmps="^".dsoencode($tmps);
		}



		$alls=$alls."\n".$tmps;
		}
		$script=$alls;
		//--------------------------------------------------------------------------------



		//replace variables
		$script = str_ireplace("\$serverdomain",$d,$script);
		$script = str_ireplace("\$serverip",getip($d),$script);


		$script=str_replace("\r","\n",$script);
		$script=str_replace("\n\n","\n",$script);
		$script=str_replace("\n\n","\n",$script);

		//encode it
		//$script = encode($script,$encodekey);

		//$script2 = decode($script,$encodekey);
		//echo "ENCRYPTED".$script2;

		die("$params::$script<end>");
		//die("$params::ENCRYPTED$script<end>");
		//die("::ENCRYPTED$script<end>");


		}else{
		//not found!
		die("Not Found<end>");	

		}

		}
		else
		{
			die('Not Found<end>');
		}
		*/
	}
	else
	{
		echo 'Access Denied';
	}
	
	echo '<end>';

?>