<?
	include "function.php";

	$returnwith = (string)(int)$_GET['returnwith'];
	
	if ($returnwith === "0")
		$returnwith = 2000;
	
	echo $returnwith;
	
	if ($auth == '1001')
	{
		$data = $_GET['data'];
		
		$data = explode('.', $data);
		
		if (sizeof($data) == 1) // its a user name.
		{
			echo $data.": Signed up on ".grab_from_users("createdate",$d)." at ".grab_from_users("createtime",$d)." from $ip.";
			echo "newline";
			echo strtoupper($d).": Last seen on the ".grab_from_users("lastseen",$d).".";
			
		}
		else if (sizeof($data) <= 4) // could be an IP.
		{
			
		}

	//is it a domain?
	if (domain_exists($d)){
		
			$ip=grab_from_domains("ip",$d);
			$ipfull=$ip;
			if (strstr($ip,".")){
				$ip=substr($ip,0,strpos($ip,".")+1); //now ip = 31.
				$tmps=substr($ipfull,strlen($ip),99);
				if (strstr($ip,".")){
					$ip=$ip.substr($tmps,0,strpos($tmps,".")+1); //now ip = 31.21		
					$ip=$ip."X.X"; //now ip = 31.55.?.?
				}else{
					$ip=$ip."X.X.X"; //now ip = 31.55.?.?
				}
			}
			
			
			echo strtoupper($d).": Registered by ".grab_from_domains("owner",$d)." ($ip) on the ".grab_from_domains("createdate",$d)." at ".grab_from_domains("createtime",$d)."."; //."newline".strtoupper($d).": Registered from $ip.";

	
	}else{
	//is it a username?
	
	
		if (username_exists($d)){
		
				
			$ip=grab_from_users("ip",$d);
			$ipfull=$ip;
			if (strstr($ip,".")){
				$ip=substr($ip,0,strpos($ip,".")+1); //now ip = 31.
				$tmps=substr($ipfull,strlen($ip),99);
				if (strstr($ip,".")){
					$ip=$ip.substr($tmps,0,strpos($tmps,".")+1); //now ip = 31.21		
					$ip=$ip."X.X"; //now ip = 31.55.?.?
				}else{
					$ip=$ip."X.X.X"; //now ip = 31.55.?.?
				}
			}
			
			
			
		
		
		}else{
		
			echo strtoupper($d).": Not Found!";
		}
	
	
	}
	

}else{

	echo "Access Denied 6233";
}


echo "<end>";




?>