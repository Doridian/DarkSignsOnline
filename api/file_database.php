<?
/*
if (isset($returnwith)){}else{$returnwith="2000";}
$returnwith=trim($returnwith);
echo $returnwith;


require("config.php");

$u=trim($u);
$p=trim($p);




if (auth()=="1001"){


	if (isset($getfile)){
		mysql_connect("localhost", $mysql_username, $mysql_password); mysql_select_db($mysql_database);
		$result=mysql_query("SELECT * from file_database where sid='$getfile' and deleted='0'")or die(mysql_error()); 
			while($row = mysql_fetch_array( $result )) {
				$sid = $row['sid'];
				$filedata = $row['filedata'];
				$fname = $row['filename'];
				$fname=str_replace("\\","",$fname);
				$fname=str_replace("/","",$fname);
				
				die("$fname:$filedata<end>");
			}
	}


	if (isset($removenow)){
		mysql_connect("localhost", $mysql_username, $mysql_password); mysql_select_db($mysql_database);
		$result=mysql_query("UPDATE file_database SET deleted='1' where sid='$removenow' and author='$u'")or die(mysql_error());  
		die("File ID $removenow was removed.<end>");
	}


	if (isset($getforremoval)){
		mysql_connect("localhost", $mysql_username, $mysql_password); mysql_select_db($mysql_database);
		$result=mysql_query("SELECT * from file_database where author='$u' and deleted='0'")or die(mysql_error());  
	
			while($row = mysql_fetch_array( $result )) {
				$cc++;
				$sid = $row['sid'];
				$title = $row['title'];
				$version = $row['version'];
				$author = $row['author'];
				$description = $row['description'];
				$cdate = $row['createdate'];								
				$ctime = $row['createtime'];

				$res=$res."$sid: $title (version $version) $cdate:--:";
			}
	
		die("$res<end>");
	}



	
	if (isset($getcategory)){
		mysql_connect("localhost", $mysql_username, $mysql_password); mysql_select_db($mysql_database);
		$result=mysql_query("SELECT * from file_database where category='$getcategory' and deleted='0'")or die(mysql_error());  
	
			while($row = mysql_fetch_array( $result )) {
				$cc++;
				$sid = $row['sid'];
				$title = $row['title'];
				$version = $row['version'];
				$author = $row['author'];
				$filesize = $row['filesize'];
				$description = $row['description'];
				$cdate = $row['createdate'];								
				$ctime = $row['createtime'];
				$fname = $row['filename'];
				$fname=str_replace("\\","",$fname);
				$fname=str_replace("/","",$fname);
				
			$res=$res.$sid.":--:".$title.":--:".$version.":--:".$filesize.":--:".$author.":--:".$fname.":--:".$description.":--:".$cdate.":--:".$ctime.":--:--:";
				
			}
			
	
		die("$res<end>");
	}
	
	
	
	if (isset($shortfilename)){
	
		mysql_connect("localhost", $mysql_username, $mysql_password); mysql_select_db($mysql_database);
		$sid=mysql_num_rows(mysql_query("SELECT sid from file_database"))+1;
		$ctime = addslashes(date('h:i A'));$ctime=str_replace("zz0","","zz".$ctime);$ctime=str_replace("zz","",$ctime);$ctime=addslashes($ctime);
		$cdate =trim( str_replace(" 0"," "," ".date('dS \of F Y')));
		$ahostname = gethostbyaddr($_SERVER['REMOTE_ADDR']);
		$aip = $_SERVER['REMOTE_ADDR'];
		$vercode=rand(1,1000).rand(1,1000).rand(1,1000).rand(1,1000);
		$timestamp=time();
		
		$description=addslashes($description);
		$title=addslashes($title);
		$category=addslashes($category);
		$shortfilename=addslashes($shortfilename);
		
		
		$sql="INSERT INTO file_database(sid, title, filename, version, filesize, author, description, createdate, createtime, ip, hostname, filedata, deleted, downloadlog, category, vercode, timestamp) VALUES ('$sid', '$title', '$shortfilename', '$version', '$filesize', '$u', '$description', '$cdate', '$ctime', '$aip', '$ahostname', '$filedata', '0', '', '$category', '$vercode', '$timestamp')";
				
		$result=mysql_query($sql)or die(mysql_error()."<end>"); 
		
		die("Upload complete!<end>");
	}
	
	
}else{
	echo "Not Authorized, Access Denied.";
	die("<end>");
}
*/


?>