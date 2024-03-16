<?php

//----------------------------------------------------------------------------------------------------------
//NOTE - when modifying this script, consider that you may need to modify domain_download.php as well!!!
//----------------------------------------------------------------------------------------------------------

require_once ('function.php');
global $db;

$write = $_REQUEST['write'];
$append = $_REQUEST['append'];
$fileserver = $_REQUEST['fileserver'];
$downloadfile = $_REQUEST['downloadfile'];

$d = trim($_REQUEST['d']);
$dInfo = getDomainInfo($d);

//if it wants to write or append or serverfile, check for a keycode
if (!empty ($write) || !empty ($append) || !empty ($fileserver)) {
	$filekeys = $dInfo[3];
	$keycode = $_REQUEST['keycode'];

	$keycode = str_replace("--and--", "&", $keycode);
	$keycode = ":" . $keycode . ":"; //3. add : and : to the end of it

	if ($keycode == "::") {
		die ("Error: Key not specified");
	}
	if (strstr($filekeys, $keycode)) {
		//file key found, remove it from the db and continue
		$filekeys = str_replace($keycode, "", $filekeys);
		//$result = $db->query("UPDATE domains set filekeys='$filekeys' where domain='$d'");

	} else {
		//access denied
		die ("2000Error - ($keycode) Invalid Server Key: " . strtoupper($d));
	}
}

$returnwith = $_REQUEST['returnwith'];
if (trim($returnwith) == "") {
	$returnwith = "2000";
}
echo $returnwith;


if (!empty ($write)) {
	write_domain_file($d, $write, $filedata, 0);
}
if (!empty ($append)) {
	write_domain_file($d, $append, $filedata, 1);
}

if (!empty ($downloadfile)) {
	echo download_domain_file($d, $downloadfile);
}

if (!empty ($fileserver)) {
	$thefiledata = download_domain_file($d, $fileserver);

	//echo $thefiledata."<br>----<br><br>";

	if ($maxlines < 0) {
		$maxlines = 99999;
	}
	if ($maxlines > 99999) {
		$maxlines = 99999;
	}
	if (trim($maxlines) == "") {
		$maxlines = 99999;
	}
	if (trim($startline) == "") {
		$startline = 1;
	}
	if (trim($startline) < 0) {
		$startline = 1;
	}

	//now, get the lines that are required.
	$fdarray = explode("*- -*", $thefiledata);
	$linesprinted = 0;
	$allstring = "";

	for ($x = 0; $x < count($fdarray); $x++) {
		$x2 = $x + 1;
		//echo what is required
		if ($startline <= $x2) {
			if ($maxlines > $linesprinted) {
				$allstring = $allstring . $fdarray[$x] . "\n";
				$linesprinted++;
			}
		}
	}
	$allstring = str_replace("\r", "*- -*", $allstring);
	$allstring = str_replace("\n", "*- -*", $allstring);
	echo $allstring;
	die ("");
}
