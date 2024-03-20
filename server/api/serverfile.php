<?php
	include_once 'function.php';
	
	if ($auth == '1001')
	{
		$action = $_REQUEST['action'];
		
		if ($action == 'upload')
		{
			if (auth_subowner_or_owner($serverfileupload)=="1001"){
					write_domain_file($serverfileupload,$filename,$filedata,0);
					die("File System Updated.");
			}else{
					die("Access Denied");
			}
		}
		else if ($action == 'downlaod')
		{
			//is the file public?
			if (strstr(substr(trim(strtolower(get_domain_file_no_auth_required($serverfiledownload,$filename))),0,9),"public")){
					//it is a public file!
					echo get_domain_file_no_auth_required($serverfiledownload,$filename);
					die("");
			}

			if (auth_subowner_or_owner($serverfiledownload)=="1001"){
					echo download_domain_file($serverfiledownload,$filename);
					die("");
			}else{
					die("Access Denied");
			}
		}
		else if ($action == 'delete')
		{
			if (auth_subowner_or_owner($serverfiledelete)=="1001"){
					echo delete_domain_file($serverfiledelete,$filename);
					die("");
			}else{
					die("Access Denied");
			}
		}
		else if ($action == 'count')
		{
			if (auth_subowner_or_owner($serverfilecount)=="1001"){
					echo count_domain_files($serverfilecount);
					die("");
			}else{
					die("Access Denied");
			}
		}
		else if ($action == 'name')
		{
			if (auth_subowner_or_owner($serverfilename)=="1001"){
					echo get_domain_file_by_index($serverfilename,$fileindex);
					die("");
			}else{
					die("Access Denied");
			}
		}
		else if ($action == 'dircount')
		{
			$data =  $_GET['data'];
			
			//global $u;
			//global $p;
				
			//    $d=getdomain($d);
			   
			
			$result = $db->query('SELECT * FROM domainfolder WHERE domain='.$data.' AND parent=0');
			
			echo $db->num_rows($result);
			echo "A";
			/*
						$result = $db->query("SELECT * from domains where domain='$d'");

								while($row = $db->fetch_assoc( $result )) {
										$files = $row['files'];
										if (strlen($files)){
												$filestuff=split(":----:",$files);
												return (count($filestuff)-1);
										}else{
												return "0"; //no such file exists dude!!
										}
								}
								*/
		}
	}
