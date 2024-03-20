<?php
include_once("function.php");
global $db;

$action = $_REQUEST['action'];

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
        die("");
}else{
        die("2001Access Denied: ".strtoupper($listprivileges)."");
}}


// removing this stuff for now.
if (isset($addprivileges)){
if (domainauth($addprivileges)=="1001"){
        echo "2001";
        $m = grab_from_domains("subowners", $addprivileges).":".$username.":";
        set_to_domains("subowners", $m, $addprivileges);
        die("Subowners Updated!");
}else{
        die("2001Access Denied: ".strtoupper($addprivileges)."");
}}


if (isset($removeprivileges)){
if (domainauth($removeprivileges)=="1001"){
        echo "2001";
        $m = str_replace(":".$username.":","",grab_from_domains("subowners", $removeprivileges));
        set_to_domains("subowners", $m, $removeprivileges);
        die("Subowners Updated!");
}else{
        die("2001Access Denied: ".strtoupper($removeprivileges)."");
}}



if (isset($transfer)){
        echo transaction($u,$transfer,$description,$amount,1);
        die("");
}


if (isset($transferstatus)){
if ($auth=="1001"){
        $result = $db->query("SELECT status from transactions where vercode='$transferstatus'");
        if ($db->num_rows($result)==1){
                while($row = $db->fetch_assoc( $result )) {$status = $row['status'];die("$status");}
        }
        die("NOT-FOUND");
}else{
        die("ACCESS-DENIED");
}}


if (isset($transferamount)){
if ($auth=="1001"){
        $result = $db->query("SELECT amount from transactions where vercode='$transferamount'");
        if ($db->num_rows($result)==1){
                while($row = $db->fetch_assoc( $result )) {$ss = $row['amount'];die("$ss");}
        }
        die("NOT-FOUND");
}else{
        die("ACCESS-DENIED");
}}



if (isset($transferdescription)){
if ($auth=="1001"){
        $result = $db->query("SELECT description from transactions where vercode='$transferdescription'");
        if ($db->num_rows($result)==1){
                while($row = $db->fetch_assoc( $result )) {$ss = $row['description'];die("$ss");}
        }
        die("NOT-FOUND");
}else{
        die("ACCESS-DENIED");
}}




if (isset($transfertousername)){
if ($auth=="1001"){
        $result = $db->query("SELECT tousername from transactions where vercode='$transfertousername'");
        if ($db->num_rows($result)==1){
                while($row = $db->fetch_assoc( $result )) {$ss = $row['tousername'];die("$ss");}
        }
        die("NOT-FOUND");
}else{
        die("ACCESS-DENIED");
}}


if (isset($transferfromusername)){
if ($auth=="1001"){
        $result = $db->query("SELECT fromusername from transactions where vercode='$transferfromusername'");
        if ($db->num_rows($result)==1){
                while($row = $db->fetch_assoc( $result )) {$ss = $row['fromusername'];die("$ss");}
        }
        die("NOT-FOUND");
}else{
        die("ACCESS-DENIED");
}}


if (isset($transferdate)){
if ($auth=="1001"){
        $result = $db->query("SELECT createdate from transactions where vercode='$transferdate'");
        if ($db->num_rows($result)==1){
                while($row = $db->fetch_assoc( $result )) {$ss = $row['createdate'];die("$ss");}
        }
        die("NOT-FOUND");
}else{
        die("ACCESS-DENIED");
}}


if (isset($transfertime)){
if ($auth=="1001"){
        $result = $db->query("SELECT createtime from transactions where vercode='$transfertime'");
        if ($db->num_rows($result)==1){
                while($row = $db->fetch_assoc( $result )) {$ss = $row['createtime'];die("$ss");}
        }
        die("NOT-FOUND");
}else{
        die("ACCESS-DENIED");
}}
