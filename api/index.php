<?
	include("function.php");
	include_once('mysql_config.php');
	global $db;

	$action = $db->real_escape_string($_REQUEST['action']);
	
// gota look into this...
if (isset($verify)){
        $db->query("UPDATE users SET emailverified='1' where emailverifycode='$verify'");
        die("Your account has been verified!");
}




if (isset($listprivileges)){
if (domainauth($listprivileges)=="1001"){
        echo "2001";
        $m = grab_from_domains("subowners", $listprivileges);
        if (trim($m)==""){
                echo "There are no subowners set for: ".strtoupper($listprivileges);
        }else{
                echo $m;
        }
        die("<end>");
}else{
        die("2001Access Denied: ".strtoupper($listprivileges)."<end>");
}}


// removing this stuff for now.
if (isset($addprivileges)){
if (domainauth($addprivileges)=="1001"){
        echo "2001";
        $m = grab_from_domains("subowners", $addprivileges).":".$username.":";
        set_to_domains("subowners", $m, $addprivileges);
        die("Subowners Updated!<end>");
}else{
        die("2001Access Denied: ".strtoupper($addprivileges)."<end>");
}}


if (isset($removeprivileges)){
if (domainauth($removeprivileges)=="1001"){
        echo "2001";
        $m = str_replace(":".$username.":","",grab_from_domains("subowners", $removeprivileges));
        set_to_domains("subowners", $m, $removeprivileges);
        die("Subowners Updated!<end>");
}else{
        die("2001Access Denied: ".strtoupper($removeprivileges)."<end>");
}}



if (isset($transfer)){
        echo transaction($u,$transfer,$description,$amount,1);
        die("<end>");
}


if (isset($transferstatus)){
if (auth()=="1001"){
        $result = $db->query("SELECT status from transactions where vercode='$transferstatus'");
        if ($db->num_rows($result)==1){
                while($row = $db->fetch_array( $result )) {$status = $row['status'];die("$status<end>");}
        }
        die("NOT-FOUND<end>");
}else{
        die("ACCESS-DENIED<end>");
}}


if (isset($transferamount)){
if (auth()=="1001"){
        $result = $db->query("SELECT amount from transactions where vercode='$transferamount'");
        if ($db->num_rows($result)==1){
                while($row = $db->fetch_array( $result )) {$ss = $row['amount'];die("$ss<end>");}
        }
        die("NOT-FOUND<end>");
}else{
        die("ACCESS-DENIED<end>");
}}



if (isset($transferdescription)){
if (auth()=="1001"){
        $result = $db->query("SELECT description from transactions where vercode='$transferdescription'");
        if ($db->num_rows($result)==1){
                while($row = $db->fetch_array( $result )) {$ss = $row['description'];die("$ss<end>");}
        }
        die("NOT-FOUND<end>");
}else{
        die("ACCESS-DENIED<end>");
}}




if (isset($transfertousername)){
if (auth()=="1001"){
        $result = $db->query("SELECT tousername from transactions where vercode='$transfertousername'");
        if ($db->num_rows($result)==1){
                while($row = $db->fetch_array( $result )) {$ss = $row['tousername'];die("$ss<end>");}
        }
        die("NOT-FOUND<end>");
}else{
        die("ACCESS-DENIED<end>");
}}


if (isset($transferfromusername)){
if (auth()=="1001"){
        $result = $db->query("SELECT fromusername from transactions where vercode='$transferfromusername'");
        if ($db->num_rows($result)==1){
                while($row = $db->fetch_array( $result )) {$ss = $row['fromusername'];die("$ss<end>");}
        }
        die("NOT-FOUND<end>");
}else{
        die("ACCESS-DENIED<end>");
}}


if (isset($transferdate)){
if (auth()=="1001"){
        $result = $db->query("SELECT createdate from transactions where vercode='$transferdate'");
        if ($db->num_rows($result)==1){
                while($row = $db->fetch_array( $result )) {$ss = $row['createdate'];die("$ss<end>");}
        }
        die("NOT-FOUND<end>");
}else{
        die("ACCESS-DENIED<end>");
}}


if (isset($transfertime)){
if (auth()=="1001"){
        $result = $db->query("SELECT createtime from transactions where vercode='$transfertime'");
        if ($db->num_rows($result)==1){
                while($row = $db->fetch_array( $result )) {$ss = $row['createtime'];die("$ss<end>");}
        }
        die("NOT-FOUND<end>");
}else{
        die("ACCESS-DENIED<end>");
}}




die("<end>");
?>
