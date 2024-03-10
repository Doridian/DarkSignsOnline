<?php
	include_once('mysql_config.php');
	global $db;

	global $user, $auth;
	global $auth_data;
	
	$u = $db->real_escape_string($_REQUEST['u']);
	$p = $db->real_escape_string($_REQUEST['p']);

	$res = $db->query("SELECT * FROM users WHERE username='$u' AND password='$p'");
	$user = $res->fetch_array();

	$auth_result = $db->query("SELECT * FROM users WHERE username='$u' AND password='$p' AND active='1'") or die("9998");  
	if ($auth_result->num_rows == 1)
	{
		$auth_data = $auth_result->fetch_array();
		//$db->query("UPDATE users SET lastseen='$cdate' WHERE username='$u' AND password='$p'");
		// account is active
		$auth = '1001';
	}
	else
	{
		$auth_result = $db->query("SELECT * FROM users WHERE username='$u' and password='$p' AND active='0'") or die("9997");  
		if ($auth_result->num_rows == 1)
		{
			//account disabled
			$auth = '1003';
		}
		else
		{
			//bad username or password
			$auth = '1002';
		}
	}

	// Rewritten.
	function validIP($ip)
	{
		global $db;
		$domain = explode('.', $ip);
		$domain[0] = intval($domain[0]);
		$domain[1] = intval($domain[1]);
		$domain[2] = intval($domain[2]);
		$domain[3] = intval($domain[3]);
			
		if ($domain[0] > 0 && $domain[0] < 256 && $domain[1] > 0 && $domain[1] < 256 && $domain[2] > 0 && $domain[2] < 256 && $domain[3] > 0 && $domain[3] < 256)
		{
			return true;
		}
		else
		{
			return false;
		}
	}
		
	// Rewritten.
	function getDomainInfo($domain)
	{
		global $db;
		$domain = explode('.', $domain);
		
		$result = null;
		
		if (sizeof($domain) == 2)
		{
			$result = $db->query("SELECT d.id, ipt.owner, d.subowners FROM domain AS d, iptable AS ipt WHERE d.name='".$domain[0]."' AND d.ext='".$domain[1]."' AND d.id=ipt.id");
		}
		else if (sizeof($domain) == 3)
		{
			$result = $db->query("SELECT s.id, ipt.owner, d.subowners FROM subdomain AS s, iptable AS ipt, domain AS d WHERE d.name='".$domain[1]."' AND d.ext='".$domain[2]."' AND d.id=s.hostid AND s.name='".$domain[0]."' AND s.id=ipt.id");
		}
		else if (sizeof($domain) == 4)
		{
			$result = $db->query("SELECT id, owner, '' FROM iptable WHERE ip='$domain[0].$domain[1].$domain[2].$domain[3]'");
		}
		else
		{
			return array(-1, -1, '');
		}

		if (!$result) {
			die($db->error);
		}

		if ($result && $result->num_rows == 1)
		{
			return $result->fetch_row();
		}
		else
		{
			return array(-1, -1, '');
		}
	}
	
	// Rewritten
	function domain_exists($domain, $ext)
	{
		global $db;
		$result = $db->query("SELECT id FROM domain WHERE name='$domain' AND ext='$ext'");
		if ($result->num_rows == 1)
		{
			return true;
		}
		else
		{
			return false;
		}
	}
	
	// Rewritten
	function getDomainId($domain, $ext)
	{
		global $db;
		$result = $db->query("SELECT id FROM domain WHERE name='$domain' AND ext='$ext'");
		if ($result->num_rows == 1)
		{
			return $result->result(0);			
		}
		else
		{
			return -1;
		}
	}
	
	// Rewritten
	function subdomain_exists($sub, $domain, $ext)
	{
		global $db;
		// This is without the .com bit.
		$domain_id = getDomainId($domain, $ext);
		
		if ($domain_id < 0)
			return false;
			
		$result = $db->query("SELECT id FROM subdomain WHERE hostid='$domain_id' AND name='$sub'") or die('DIED');
		if ($db->num_rows($result) == 1)
		{
			return true;
		}
		else
		{
			return false;
		}
	}
        
	// rewritten.
	function getOwner($domain, $ext)
	{
		global $db;
		$result = $db->query("SELECT i.owner FROM domain AS d, iptable AS i WHERE d.name='$domain' AND d.ext='$ext' AND d.id=i.id");
		if ($db->num_rows($result) == 1)
		{
			return $db->result($result, 0);			
		}
		else
		{
			return -1;
		}
	}

	// Rewritten.
	function auth_subowner_or_owner($domain)
	{
		global $db;
        if ($auth == '1001')
        {
			$ip = getip($domain);
			
			if ($ip == '0' || $ip == '1')
			{
				return '1003';
			}
			
			$result = $db->query("SELECT owner FROM iptable WHERE ip='$ip' and owner='$user[id]'") or die('QUERY FAILED');
			
			if ($db->num_rows($result) == 1)
			{
				//it's the owner, allow it
				return "1001";
			}
			else
			{
				return '1003';
			}
			/*
			else
			{
				//check subowners
				$subowners = $db->fetch_array($db->query("SELECT subowners FROM domains WHERE domain='$d'"));

				if (strstr($subowners[0], ':'.$u.':'))
				{
					//subowner found, continue!
					return '1001';
				}
				else
				{                
					return '1003';
				}
			}
			*/    
        }
        else
        {
			return '1004';
        }
	}

function grab_from_users($field, $usern="")
{
	global $db;
        global $u;
        global $p;
        
        if ($usern == "")
        {
                $usern = $u;
        }
        
        if (strtolower(trim($field)) == 'password')
        {
                //for security, just in case ;)
                die;
        }
                
        if ($auth == '1001')
        {
                $result = $db->fetch_array($db->query("SELECT $field FROM users WHERE username='$usern' AND enabled='1'")) or die('Query Error');  
                return $result[0];
        }
        else
        {
                return 'Access Denied.';
        }
}


function domainauth($d){
        global $u;
        global $p;
        
		global $db;
        if (auth($u,$p)=="1001"){

                if ($db->num_rows($db->query("SELECT id from domains where domain='$d' and owner='$u'"))>0){
                        return "1001";
                }else{
                        if (strtolower($u)=="admin"){
                                return "1001"; // the admin is ALWAYS authorized :)
                        }else{
                                return "1002";
                        }
                }
                while($row = $db->fetch_array( $result )) {$ret = trim($row[$field]);}
                return $ret;
        }else{
                return "1002";
        }
}


function grab_from_domains($field, $domain){



	global $db;
        global $u;
        global $p;
        
        if (auth($u,$p)=="1001"){

                $result=$db->query("SELECT $field from domains where domain='$domain'")or die($db->error);  
                while($row = $db->fetch_array( $result )) {$ret = trim($row[$field]);}
                return $ret;
        }else{
                return "Access Denied.";
        }
}


function get_domain_file($d,$filename){



	global $db;
        global $u;
        global $p;
        
        $filename=trim(strtolower($filename));
        $d=getdomain($d);
        
        if (domainauth($d)=="1001"){
        

                $result = $db->query("SELECT * from domains where domain='$d'");

                        while($row = $db->fetch_array( $result )) {
                                $files = $row['files'];

                                if (strlen($files)){
                                        $filestuff=split(":----:",$files);

                                        for ($x=0; $x < count($filestuff);$x++){
                                        
                                                if (strlen($filestuff[$x])>0){
                                                
                                                        $thefile = split(":---:",$filestuff[$x]);
                                                        $sfilename = trim(strtolower($thefile[0]));
                                                        $sfiledata = trim($thefile[1]);
                                                        
                                                        if ($sfilename==$filename){
                                                                //this is the file!
                                                                if (trim($sfiledata)==""){
                                                                        return "//empty";
                                                                }else{
                                                                        return $sfiledata;
                                                                }
                                                        }
                                                }
                                        }
                                }else{
                                        return ""; //no such file exists dude!!
                                }
                        }
                
        }else{
                return "";
        }
}


        

function get_domain_file_by_index($d,$fileindex){



	global $db;
        global $u;
        global $p;
        

        $d=getdomain($d);

        

                $result = $db->query("SELECT * from domains where domain='$d'");

                        while($row = $db->fetch_array( $result )) {
                                $files = $row['files'];

                                if (strlen($files)){
                                        $filestuff=split(":----:",$files);
                                        $filecounter=0;
                                        
                                        for ($x=0; $x < count($filestuff);$x++){
                                                if (strlen($filestuff[$x])>0){
                                                        
                                                        $filecounter++;
                                                        
                                                        $thefile = split(":---:",$filestuff[$x]);
                                                        $sfilename = trim(strtolower($thefile[0]));
                                                        //$sfiledata = trim($thefile[1]);
                                                        
                                                        if ($filecounter==$fileindex){
                                                                //this is it, return the filename
                                                                return $sfilename;
                                                        }
                                                }
                                        }
                                }else{
                                        return ""; //no such file exists dude!!
                                }
                        }

}



function count_domain_files($d){



	global $db;
        global $u;
        global $p;
        
        $d=getdomain($d);
        

                $result = $db->query("SELECT * from domains where domain='$d'");

                        while($row = $db->fetch_array( $result )) {
                                $files = $row['files'];
                                if (strlen($files)){
                                        $filestuff=split(":----:",$files);
                                        return (count($filestuff)-1);
                                }else{
                                        return "0"; //no such file exists dude!!
                                }
                        }
}



function filekey($d,$tmps){
        
        //$tmps is the line, e.g. SERVER WRITE file.dat ($tmps generally isn't used unless bug testing)
        
		global $db;
        global $encodekey;
        
        $newkey=$vercode=rand(1,1000).rand(1,1000).rand(1,1000).rand(1,1000).rand(1,1000);
        

        //validate the new key into the database
        $result = $db->query("SELECT filekeys from domains where domain='$d'");

                while($row = $db->fetch_array( $result )) {
                        $filekeys = $filekeys.$row['filekeys'];
                }
        


        $newkey2=dsoencode($newkey);


        $filekeys=$filekeys.":".$newkey2.":\n";


        $result = $db->query("UPDATE domains set filekeys='$filekeys' where domain='$d'");
                
        //return the short key, it wil be converted to a long key by the client
        return $newkey;
        
        

}


function write_domain_file($d,$filename,$filedata,$appendifexists){



	global $db;
        global $u;
        global $p;
        
        $filename=trim(strtolower($filename));
        $d=getdomain($d);
        
        //if (domainauth($d)=="1001"){ ----------

                $result2 = $db->query("SELECT * FROM domains where domain='$d'") or die($db->error);  
                

                        while($row = $db->fetch_array( $result2 )) {
                                $files = $row['files'];

                                if (strlen($files)){
                                        $filestuff=split(":----:",$files);

                                        for ($x=0; $x < count($filestuff);$x++){
                                        
                                                if (strlen($filestuff[$x])>0){
                                                
                                                        $thefile = split(":---:",$filestuff[$x]);
                                                        $sfilename = trim(strtolower($thefile[0]));
                                                        $sfiledata = trim($thefile[1]);
                                                        
                                                        if ($sfilename==$filename){
                                                                //this is the file!
                                                                if ($appendifexists==1){
                                                                        $sfiledata=$sfiledata."\n".$filedata;
                                                                        $haswritten=1;
                                                                }else{
                                                                        $sfiledata=$filedata;
                                                                        $haswritten=1;
                                                                }
                                                        }
                                                        
                                                        $alldata = $alldata.":----:$sfilename:---:$sfiledata";
                                                }
                                        }
                                        
                                        if($haswritten==1){}else{$alldata = $alldata.":----:$filename:---:$filedata";}
                                        
                                        
                                        
                                }else{
                                        //no such file exists dude!! write it
                                        $alldata = $alldata.":----:$filename:---:$filedata";
                                }
                                

                        $result = $db->query("UPDATE domains set files='$alldata' where domain='$d'");
                        
                        }
                
        //}else{
        //        return "";
        //} ----------
}



function delete_domain_file($d,$filename){



	global $db;
        global $u;
        global $p;
        
        $filename=trim(strtolower($filename));
        $d=getdomain($d);
        
        //if (domainauth($d)=="1001"){ ----------

                $result2 = $db->query("SELECT * FROM domains where domain='$d'") or die($db->error);  
                
                        $removed=0;
                        while($row = $db->fetch_array( $result2 )) {
                                $files = $row['files'];

                                if (strlen($files)){
                                        $filestuff=split(":----:",$files);

                                        for ($x=0; $x < count($filestuff);$x++){
                                        
                                                if (strlen($filestuff[$x])>0){
                                                
                                                        $thefile = split(":---:",$filestuff[$x]);
                                                        $sfilename = trim(strtolower($thefile[0]));
                                                        $sfiledata = trim($thefile[1]);
                                                        
                                                        if ($sfilename==$filename){
                                                                $removed=1;
                                                                //this is the file!, don't write it!
                                                        }else{
                                                                $alldata = $alldata.":----:$sfilename:---:$sfiledata";                                                        
                                                        }
                                                        

                                                }
                                        }
                                        
                                        //if($haswritten==1){}else{$alldata = $alldata.":----:$filename:---:$filedata";}
                                }
                                

                        $result = $db->query("UPDATE domains set files='$alldata' where domain='$d'");
                        
                        if ($removed==1){
                                return "File System Updated.";
                        }else{
                                return "File Not Found.";
                        }
                        
                        
                        }
}



function download_domain_file($d,$filename){



	global $db;
        global $u;
        global $p;
        
        $filename=trim(strtolower($filename));
        $d=getdomain($d);

        if (auth_subowner_or_owner($d)=="1001"){ 

                $result2 = $db->query("SELECT * FROM domains where domain='$d'") or die($db->error);  


                        $filefound=0;
                        while($row = $db->fetch_array( $result2 )) {
                                $files = $row['files'];

                                if (strlen($files)){
                                        $filestuff=split(":----:",$files);

                                        

                                        for ($x=0; $x < count($filestuff);$x++){
                                        
                                                if (strlen($filestuff[$x])>0){
                                                
                                                        $thefile = split(":---:",$filestuff[$x]);
                                                        $sfilename = trim(strtolower($thefile[0]));
                                                        $sfiledata = trim($thefile[1]);
                                                        
                                                                        if (trim(strtolower($sfilename))==trim(strtolower($filename))){
                                                                        //this is the file, return the data and leave!
                                                                                $filefound=1;
                                                                                $alldata = $alldata.str_replace("\n","*- -*",$sfiledata);
                                                                        }
                                                        
        
                                                }
                                        }
                                        
                                        if ($filefound==1){
                                                $alldata=str_replace("\r","",$alldata);
                                                return $alldata;
                                        }else{
                                                return "File Not Found: ".strtoupper($filename);
                                        }
                                        
                                }
                        }
                        
                        return "File Not Found: ".strtoupper($filename);
                
                
        }else{
                return "Not Authorized: ".strtoupper($d);
        } 
}






function get_domain_file_no_auth_required($d,$filename){



	global $db;
        global $u;
        global $p;
        
        $filename=trim(strtolower($filename));$d=getdomain($d);
                $result2 = $db->query("SELECT * FROM domains where domain='$d'") or die($db->error);  

                        $filefound=0;
                        while($row = $db->fetch_array( $result2 )) {
                                $files = $row['files'];

                                if (strlen($files)){
                                        $filestuff=split(":----:",$files);

                                        for ($x=0; $x < count($filestuff);$x++){
                                        
                                                if (strlen($filestuff[$x])>0){
                                                
                                                        $thefile = split(":---:",$filestuff[$x]);
                                                        $sfilename = trim(strtolower($thefile[0]));
                                                        $sfiledata = trim($thefile[1]);
                                                        
                                                        if (trim(strtolower($sfilename))==trim(strtolower($filename))){
                                                                $filefound=1;
                                                                $alldata = $alldata.str_replace("\n","*- -*",$sfiledata);
                                                        }
                                                }
                                        }
                                        
                                        if ($filefound==1){
                                                $alldata=str_replace("\r","",$alldata);
                                                return $alldata;
                                        }else{
                                                return "File Not Found: ".strtoupper($filename);
                                        }
                                        
                                }
                        }
                        
                        return "File Not Found: ".strtoupper($filename);

}








function listdomains(){

	global $db;
        global $user;
        global $u;
        global $p;
        if (auth()=="1001"){
        
                $result = $db->query("SELECT dom.name AS dname, dom.ext AS dext FROM iptable AS ipt, domain AS dom WHERE ipt.owner='$user[id]' AND dom.id = ipt.id");
                echo "2001";
                //echo "SELECT dom.name AS dname, dom.ext AS dext FROM iptable AS ipt, domain AS dom WHERE ipt.owner='$user[id]' AND dom.id = ipt.id";
                while($row = $db->fetch_array( $result )) {
                        $tmps="$row[dname].$row[dext]";
                        echo $tmps."newline";
                }
        
        }
        
}



	// Rewritten.
	function getip($server)
	{
		global $db;
		$svr = explode('.', $server);
		if (count($svr) == 2)
		{
			$result = $db->query("SELECT ipt.ip AS ip FROM iptable AS ipt, domain AS dom WHERE dom.name='$svr[0]' AND dom.ext='$svr[1]' AND ipt.id = dom.id");			
		}
		else if (count($svr) == 3)
		{
			$result = $db->query("SELECT ipt.ip AS ip FROM iptable AS ipt, domain AS dom, subdomain AS sub WHERE dom.name='$svr[1]' AND dom.ext='$svr[2]' AND sub.name='$svr[0]' AND sub.hostid = dom.id AND ipt.id = sub.id");				
		}
		else if (count($svr) == 4)
		{
			$result = $db->query("SELECT ip FROM iptable WHERE ip='$svr[0].$svr[1].$svr[2].$svr[3]'");			
		}

		// Everything went fine.
		if (count($svr) >= 2 && count($svr) <= 4)
		{
			if ($db->num_rows($result) == 1)
			{
				return $db->result($result, 0);
			}
			else // domain dosnt exist.
			{
				return '1';	
			}
		}
		else // invalid syntax.
		{
			return '0';
			
		}
	}

	// re-written
	function getdomain($server)
	{
		global $db;
		$svr = explode('.', $server);
		if (count($svr) == 2)
		{
			$result = $db->query("SELECT name, ext FROM domain WHERE name='$svr[0]' AND ext='$svr[1]' AND active=1");
		}
		else if (count($svr) == 3)
		{
			$result = $db->query("SELECT sub.name AS sname, dom.name AS dname, dom.ext AS ext FROM domain AS dom, subdomain AS sub WHERE dom.name='$svr[1]' AND dom.ext='$svr[2]' AND sub.name='$svr[0]' AND sub.hostid = dom.id AND sub.active=1");				
		}
		else if (count($svr) == 4)
		{
			$result = $db->query("SELECT id, regtype FROM iptable WHERE ip='$svr[0].$svr[1].$svr[2].$svr[3]' AND active=1");			
		}

		// Everything went fine.
		//echo count($svr);
		if (count($svr) >= 2 && count($svr) <= 4)
		{
			if ($db->num_rows($result) == 1)
			{
				$data = $db->fetch_array($result);
				if (count($svr) == 2)
				{
					return $data['name'].'.'.$data['ext'];				
				}
				else if (count($svr) == 3)
				{
					return $data['sname'].'.'.$data['dname'].'.'.$data['ext'];
				}
				else if (count($svr) == 4)
				{
					if ($data['regtype'] == 'SUBDOMAIN')
					{
						$data = $db->fetch_array($db->query("SELECT sub.name AS sname, dom.name AS dname, dom.ext AS ext FROM domain AS dom, subdomain AS sub WHERE sub.id='$data[id]' AND dom.id=sub.hostid AND sub.active=1"));
						return $data['sname'].'.'.$data['dname'].'.'.$data['ext'];				
					}
					else if ($data['regtype'] == 'DOMAIN')
					{
						$data = $db->fetch_array($db->query("SELECT name, ext FROM domain WHERE id='$data[id]'  AND active=1"));
						return $data['name'].'.'.$data['ext'];
					}
					else
					{
						return $svr[0].'.'.$svr[1].'.'.$svr[2].'.'.$svr[3];
						
					}
				}
				//return $db->result($result, 0);
			}
			else // domain dosnt exist.
			{
				return '1';	
			}
		}
		else // invalid syntax.
		{
			return '0';
		}
	}

	// Re-written.
	function username_exists($username)
	{
		global $db;
		$result = $db->query("SELECT username FROM users WHERE username='$username'");
		if ($db->num_rows($result) == 0)
		{
			return false;
		}
		else
		{
			return true;
		}
	}

        
        function domain_owner($owner, $domain, $ext)
        {
			global $db;
                // This is without the .com bit.
                $result = $db->query("SELECT * FROM domain WHERE owner='$owner' AND name='$domain' AND ext='$ext'") or die('DIED');
                echo $owner;
                if ($db->num_rows($result) == 0)
                {
                        return false;
                }
                else
                {
                        return true;
                }
        }
     
	// Re-written
	function userToId($username)
	{
		$result = $db->query("SELECT id FROM users WHERE username='$username'");
		if ($db->num_rows($result) == 1)
		{
			return $db->result($result, 0);
		}
		else
		{
			return -1;
		}
	}
	
	// Re-written
	function idToUser($id)
	{
		global $db;
		$result = $db->query("SELECT username FROM users WHERE id='$id'");
		if ($db->num_rows($result) == 1)
		{
			return $db->result($result, 0);
		}
		else
		{
			return -1;
		}
	}
	
	
	// Rewritten.
	function getCash($user_id)
	{
		global $db;
		$result = $db->query("SELECT cash FROM users WHERE id='$user_id'");
		if ($result->num_rows === 1)
		{
			return $result->fetch_row()[0];
		}
		else
		{
			return 0;			
		}		
	}
	
	// Rewritten.
	function transaction($fromuser, $touser, $description, $amount, $returnkeycodeinstead = 0)
	{
		global $db;
		$from_id = userToId($fromuser);
		$to_id = userToId($touser);
		$description = addslashes($description);
		$vercode = rand(100,999).rand(100,999).rand(100,999).rand(100,999).rand(100,999);
								
		if ($from_id > 0 && $to_id > 0 && $from_id != $to_id)
		{
			if ($amount > 0)
			{
				$from_cash = getCash($from_id);
				$to_cash = getCash($to_id);
				
				if ($from_cash  < $amount)
				{
					// Insufficient Funds
					$status = 'INSUFFICIENT';
				}
				else
				{
					$db->query("UPDATE users SET cash=cash-$amount WHERE id=$from_id");
					$db->query("UPDATE users SET cash=cash+$amount WHERE id=$to_id");
					$status = 'COMPLETE';
				}
			}
			else
			{
				// Cant send negative DSD.
				$status = 'INVALID-AMOUNT';
			}
		}
		else
		{
			if ($from_id == -1)
			{
				// Invalid from user id.
				$status = "INVALID-SENDER";
			}
			else if ($to_id == -1)
			{
				// Invalid to user id.
				$status = "INVALID-RECEIVER";
			}
			else
			{
				// Cant send money to yourself.
				$status = "INVALID-USER";
			}
		}
		
		$time = time();
		$ip = $_SERVER['REMOTE_ADDR'];
		$db->query("INSERT INTO transactions (fromid, toid, amount, description, vercode, `time`, status, ip) VALUES ($from_id, $to_id, $amount, '$description', '$vercode', '$time', '$status', '$ip')") or die ($db->error);

		if ($returnkeycodeinstead == 1)
		{
			return $vercode;
		}
		else
		{
			if ($status == 'COMPLETE')
			{
					return true;
			}
			else
			{
					return false;
			}
		}
	}
?>