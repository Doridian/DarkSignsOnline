<?php

die('This file is for reference use only!!!');

// Rewritten
function subdomain_exists($sub, $domain, $ext)
{
	global $db;
	// This is without the .com bit.
	$domain_id = getDomainId($domain, $ext);

	if ($domain_id < 0)
		return false;

	$stmt = $db->prepare("SELECT id FROM subdomain WHERE hostid=? AND name=?");
	$stmt->bind_param('is', $domain_id, $sub);
	$stmt->execute();
	$result = $stmt->get_result();
	if ($db->num_rows($result) == 1) {
		return true;
	} else {
		return false;
	}
}

// rewritten.
function getOwner($domain, $ext)
{
	global $db;
	$stmt = $db->prepare("SELECT ipt.owner FROM domain d, iptable ipt WHERE d.name=? AND d.ext=? AND d.id=ipt.id");
	$stmt->bind_param('ss', $domain, $ext);
	$stmt->execute();
	$result = $stmt->get_result();
	if ($db->num_rows($result) == 1) {
		return $result->fetch_row()[0];
	} else {
		return -1;
	}
}

function auth_subowner_or_owner($domain)
{
	global $db;
	global $user;
	global $auth;
	if ($auth == '1001') {
		$ip = getip($domain);

		if ($ip == '0' || $ip == '1') {
			return '1003';
		}

		$stmt = $db->prepare("SELECT owner FROM iptable WHERE ip=? AND owner=?");
		$stmt->bind_param('si', $ip, $user['id']);
		$stmt->execute();
		$result = $stmt->get_result();

		if ($result->num_rows == 1) {
			//it's the owner, allow it
			return "1001";
		} else {
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
	} else {
		return '1004';
	}
}

function grab_from_users($field, $usern = "")
{
	global $db;
	global $auth;
	global $u;

	if ($usern == "") {
		$usern = $u;
	}

	if (strtolower(trim($field)) == 'password') {
		//for security, just in case ;)
		die;
	}

	if ($auth == '1001') {
		$stmt = $db->prepare("SELECT ? FROM users WHERE username=? AND active='1'");
		$stmt->bind_param('ss', $field, $usern);
		$stmt->execute();
		$result = $stmt->get_result();
		$row = $result->fetch_row();
		return $row[0];
	} else {
		return 'Access Denied.';
	}
}


function domainauth($d)
{
	global $user;
	global $db;
	global $auth;

	if ($auth == "1001") {
		$stmt = $db->prepare("SELECT id FROM domains WHERE domain=? AND owner=?");
		$stmt->bind_param('si', $d, $user['id']);
		$stmt->execute();
		$res = $stmt->get_result();
		if ($res->num_rows > 0) {
			return "1001";
		} else {
			return "1002";
		}
		while ($row = $db->fetch_array($result)) {
			$ret = trim($row[$field]);
		}
		return $ret;
	} else {
		return "1002";
	}
}


function grab_from_domains($field, $domain)
{
	global $db;
	global $auth;

	if ($auth === "1001") {
		$result = $db->query("SELECT $field from domains where domain='$domain'") or die($db->error);
		while ($row = $db->fetch_array($result)) {
			$ret = trim($row[$field]);
		}
		return $ret;
	} else {
		return "Access Denied.";
	}
}


function get_domain_file($d, $filename)
{



	global $db;
	global $u;
	global $p;

	$filename = trim(strtolower($filename));
	$d = getdomain($d);

	//if (domainauth($d)=="1001"){


	$result = $db->query("SELECT * from domains where domain='$d'");

	while ($row = $db->fetch_array($result)) {
		$files = $row['files'];

		if (strlen($files)) {
			$filestuff = explode(":----:", $files);

			for ($x = 0; $x < count($filestuff); $x++) {

				if (strlen($filestuff[$x]) > 0) {

					$thefile = explode(":---:", $filestuff[$x]);
					$sfilename = trim(strtolower($thefile[0]));
					$sfiledata = trim($thefile[1]);

					if ($sfilename == $filename) {
						//this is the file!
						if (trim($sfiledata) == "") {
							return "//empty";
						} else {
							return $sfiledata;
						}
					}
				}
			}
		} else {
			return ""; //no such file exists dude!!
		}
	}

	//}else{
	//        return "";
	//}
}




function get_domain_file_by_index($d, $fileindex)
{



	global $db;
	global $u;
	global $p;


	$d = getdomain($d);



	$result = $db->query("SELECT * from domains where domain='$d'");

	while ($row = $db->fetch_array($result)) {
		$files = $row['files'];

		if (strlen($files)) {
			$filestuff = explode(":----:", $files);
			$filecounter = 0;

			for ($x = 0; $x < count($filestuff); $x++) {
				if (strlen($filestuff[$x]) > 0) {

					$filecounter++;

					$thefile = explode(":---:", $filestuff[$x]);
					$sfilename = trim(strtolower($thefile[0]));
					//$sfiledata = trim($thefile[1]);

					if ($filecounter == $fileindex) {
						//this is it, return the filename
						return $sfilename;
					}
				}
			}
		} else {
			return ""; //no such file exists dude!!
		}
	}
}



function count_domain_files($d)
{



	global $db;
	global $u;
	global $p;

	$d = getdomain($d);


	$result = $db->query("SELECT * from domains where domain='$d'");

	while ($row = $db->fetch_array($result)) {
		$files = $row['files'];
		if (strlen($files)) {
			$filestuff = explode(":----:", $files);
			return (count($filestuff) - 1);
		} else {
			return "0"; //no such file exists dude!!
		}
	}
}

function dsoencode($str)
{
	return $str; // TODO: What does this do?
}

function filekey($d, $tmps)
{
	//$tmps is the line, e.g. SERVER WRITE file.dat ($tmps generally isn't used unless bug testing)

	global $db;
	global $encodekey;

	$newkey = $vercode = rand(1, 1000) . rand(1, 1000) . rand(1, 1000) . rand(1, 1000) . rand(1, 1000);


	//validate the new key into the database
	$result = $db->query("SELECT filekeys from domains where domain='$d'");

	while ($row = $db->fetch_array($result)) {
		$filekeys = $filekeys . $row['filekeys'];
	}

	$newkey2 = dsoencode($newkey);

	$filekeys = $filekeys . ":" . $newkey2 . ":\n";


	$result = $db->query("UPDATE domains set filekeys='$filekeys' where domain='$d'");

	//return the short key, it wil be converted to a long key by the client
	return $newkey;
}


function write_domain_file($d, $filename, $filedata, $appendifexists)
{
	global $db;
	global $u;
	global $p;

	$filename = trim(strtolower($filename));
	$d = getdomain($d);

	//if (domainauth($d)=="1001"){ ----------

	$result2 = $db->query("SELECT * FROM domains where domain='$d'") or die($db->error);


	while ($row = $db->fetch_array($result2)) {
		$files = $row['files'];

		if (strlen($files)) {
			$filestuff = explode(":----:", $files);

			for ($x = 0; $x < count($filestuff); $x++) {

				if (strlen($filestuff[$x]) > 0) {

					$thefile = explode(":---:", $filestuff[$x]);
					$sfilename = trim(strtolower($thefile[0]));
					$sfiledata = trim($thefile[1]);

					if ($sfilename == $filename) {
						//this is the file!
						if ($appendifexists == 1) {
							$sfiledata = $sfiledata . "\n" . $filedata;
							$haswritten = 1;
						} else {
							$sfiledata = $filedata;
							$haswritten = 1;
						}
					}

					$alldata = $alldata . ":----:$sfilename:---:$sfiledata";
				}
			}

			if ($haswritten == 1) {
			} else {
				$alldata = $alldata . ":----:$filename:---:$filedata";
			}
		} else {
			//no such file exists dude!! write it
			$alldata = $alldata . ":----:$filename:---:$filedata";
		}


		$result = $db->query("UPDATE domains set files='$alldata' where domain='$d'");
	}

	//}else{
	//        return "";
	//} ----------
}



function delete_domain_file($d, $filename)
{



	global $db;
	global $u;
	global $p;

	$filename = trim(strtolower($filename));
	$d = getdomain($d);

	//if (domainauth($d)=="1001"){ ----------

	$result2 = $db->query("SELECT * FROM domains where domain='$d'") or die($db->error);

	$removed = 0;
	while ($row = $db->fetch_array($result2)) {
		$files = $row['files'];

		if (strlen($files)) {
			$filestuff = explode(":----:", $files);

			for ($x = 0; $x < count($filestuff); $x++) {

				if (strlen($filestuff[$x]) > 0) {

					$thefile = explode(":---:", $filestuff[$x]);
					$sfilename = trim(strtolower($thefile[0]));
					$sfiledata = trim($thefile[1]);

					if ($sfilename == $filename) {
						$removed = 1;
						//this is the file!, don't write it!
					} else {
						$alldata = $alldata . ":----:$sfilename:---:$sfiledata";
					}
				}
			}

			//if($haswritten==1){}else{$alldata = $alldata.":----:$filename:---:$filedata";}
		}


		$result = $db->query("UPDATE domains set files='$alldata' where domain='$d'");

		if ($removed == 1) {
			return "File System Updated.";
		} else {
			return "File Not Found.";
		}
	}
}



function download_domain_file($d, $filename)
{
	global $db;
	global $u;
	global $p;

	$filename = trim(strtolower($filename));
	$d = getdomain($d);

	if (auth_subowner_or_owner($d) == "1001") {

		$result2 = $db->query("SELECT * FROM domains where domain='$d'") or die($db->error);


		$filefound = 0;
		while ($row = $db->fetch_array($result2)) {
			$files = $row['files'];

			if (strlen($files)) {
				$filestuff = explode(":----:", $files);



				for ($x = 0; $x < count($filestuff); $x++) {

					if (strlen($filestuff[$x]) > 0) {

						$thefile = explode(":---:", $filestuff[$x]);
						$sfilename = trim(strtolower($thefile[0]));
						$sfiledata = trim($thefile[1]);

						if (trim(strtolower($sfilename)) == trim(strtolower($filename))) {
							//this is the file, return the data and leave!
							$filefound = 1;
							$alldata = $alldata . str_replace("\n", "*- -*", $sfiledata);
						}
					}
				}

				if ($filefound == 1) {
					$alldata = str_replace("\r", "", $alldata);
					return $alldata;
				} else {
					return "File Not Found: " . strtoupper($filename);
				}
			}
		}

		return "File Not Found: " . strtoupper($filename);
	} else {
		return "Not Authorized: " . strtoupper($d);
	}
}






function get_domain_file_no_auth_required($d, $filename)
{
	global $db;
	global $u;
	global $p;

	$filename = trim(strtolower($filename));
	$d = getdomain($d);
	$result2 = $db->query("SELECT * FROM domains where domain='$d'") or die($db->error);

	$filefound = 0;
	while ($row = $db->fetch_array($result2)) {
		$files = $row['files'];

		if (strlen($files)) {
			$filestuff = explode(":----:", $files);

			for ($x = 0; $x < count($filestuff); $x++) {

				if (strlen($filestuff[$x]) > 0) {

					$thefile = explode(":---:", $filestuff[$x]);
					$sfilename = trim(strtolower($thefile[0]));
					$sfiledata = trim($thefile[1]);

					if (trim(strtolower($sfilename)) == trim(strtolower($filename))) {
						$filefound = 1;
						$alldata = $alldata . str_replace("\n", "*- -*", $sfiledata);
					}
				}
			}

			if ($filefound == 1) {
				$alldata = str_replace("\r", "", $alldata);
				return $alldata;
			} else {
				return "File Not Found: " . strtoupper($filename);
			}
		}
	}

	return "File Not Found: " . strtoupper($filename);
}








function listdomains()
{
	global $db;
	global $auth;
	global $user;
	if ($auth == "1001") {

		$result = $db->query("SELECT dom.name AS dname, dom.ext AS dext FROM iptable AS ipt, domain AS dom WHERE ipt.owner='$user[id]' AND dom.id = ipt.id");
		echo "2001";
		//echo "SELECT dom.name AS dname, dom.ext AS dext FROM iptable AS ipt, domain AS dom WHERE ipt.owner='$user[id]' AND dom.id = ipt.id";
		while ($row = $db->fetch_array($result)) {
			$tmps = "$row[dname].$row[dext]";
			echo $tmps . "newline";
		}
	}
}



// Rewritten.
function getip($server)
{
	global $db;
	$svr = explode('.', $server);
	if (count($svr) == 2) {
		$result = $db->query("SELECT ipt.ip AS ip FROM iptable AS ipt, domain AS dom WHERE dom.name='$svr[0]' AND dom.ext='$svr[1]' AND ipt.id = dom.id");
	} else if (count($svr) == 3) {
		$result = $db->query("SELECT ipt.ip AS ip FROM iptable AS ipt, domain AS dom, subdomain AS sub WHERE dom.name='$svr[1]' AND dom.ext='$svr[2]' AND sub.name='$svr[0]' AND sub.hostid = dom.id AND ipt.id = sub.id");
	} else if (count($svr) == 4) {
		$result = $db->query("SELECT ip FROM iptable WHERE ip='$svr[0].$svr[1].$svr[2].$svr[3]'");
	}

	// Everything went fine.
	if (count($svr) >= 2 && count($svr) <= 4) {
		if ($db->num_rows($result) == 1) {
			return $db->result($result, 0);
		} else // domain dosnt exist.
		{
			return '1';
		}
	} else // invalid syntax.
	{
		return '0';
	}
}

// re-written
function getdomain($server)
{
	global $db;
	$svr = explode('.', $server);
	if (count($svr) == 2) {
		$result = $db->query("SELECT name, ext FROM domain WHERE name='$svr[0]' AND ext='$svr[1]' AND active=1");
	} else if (count($svr) == 3) {
		$result = $db->query("SELECT sub.name AS sname, dom.name AS dname, dom.ext AS ext FROM domain AS dom, subdomain AS sub WHERE dom.name='$svr[1]' AND dom.ext='$svr[2]' AND sub.name='$svr[0]' AND sub.hostid = dom.id AND sub.active=1");
	} else if (count($svr) == 4) {
		$result = $db->query("SELECT id, regtype FROM iptable WHERE ip='$svr[0].$svr[1].$svr[2].$svr[3]' AND active=1");
	}

	// Everything went fine.
	//echo count($svr);
	if (count($svr) >= 2 && count($svr) <= 4) {
		if ($db->num_rows($result) == 1) {
			$data = $db->fetch_array($result);
			if (count($svr) == 2) {
				return $data['name'] . '.' . $data['ext'];
			} else if (count($svr) == 3) {
				return $data['sname'] . '.' . $data['dname'] . '.' . $data['ext'];
			} else if (count($svr) == 4) {
				if ($data['regtype'] == 'SUBDOMAIN') {
					$data = $db->fetch_array($db->query("SELECT sub.name AS sname, dom.name AS dname, dom.ext AS ext FROM domain AS dom, subdomain AS sub WHERE sub.id='$data[id]' AND dom.id=sub.hostid AND sub.active=1"));
					return $data['sname'] . '.' . $data['dname'] . '.' . $data['ext'];
				} else if ($data['regtype'] == 'DOMAIN') {
					$data = $db->fetch_array($db->query("SELECT name, ext FROM domain WHERE id='$data[id]'  AND active=1"));
					return $data['name'] . '.' . $data['ext'];
				} else {
					return $svr[0] . '.' . $svr[1] . '.' . $svr[2] . '.' . $svr[3];
				}
			}
			//return $db->result($result, 0);
		} else // domain dosnt exist.
		{
			return '1';
		}
	} else // invalid syntax.
	{
		return '0';
	}
}

// Re-written.
function username_exists($username)
{
	global $db;
	$result = $db->query("SELECT username FROM users WHERE username='$username'");
	if ($db->num_rows($result) == 0) {
		return false;
	} else {
		return true;
	}
}


function domain_owner($owner, $domain, $ext)
{
	global $db;
	// This is without the .com bit.
	$result = $db->query("SELECT * FROM domain WHERE owner='$owner' AND name='$domain' AND ext='$ext'") or die('DIED');
	echo $owner;
	if ($db->num_rows($result) == 0) {
		return false;
	} else {
		return true;
	}
}

// Re-written
function userToId($username)
{
	global $db;
	$result = $db->query("SELECT id FROM users WHERE username='$username'");
	if ($db->num_rows($result) == 1) {
		return $db->result($result, 0);
	} else {
		return -1;
	}
}

// Re-written
function idToUser($id)
{
	global $db;
	$result = $db->query("SELECT username FROM users WHERE id='$id'");
	if ($db->num_rows($result) == 1) {
		return $db->result($result, 0);
	} else {
		return -1;
	}
}
