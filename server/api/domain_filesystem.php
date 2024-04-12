<?php

//----------------------------------------------------------------------------------------------------------
//NOTE - when modifying this script, consider that you may need to modify domain_download.php as well!!!
//----------------------------------------------------------------------------------------------------------

$rewrite_done = true;
require_once("function.php");
global $db;

$d = trim($_REQUEST['d']);
$dInfo = getDomainInfo($d);

print_returnwith();

function verify_keycode($filename, $opname, $require_owner = false) {
	global $db, $d, $dInfo, $user;
	$is_owner = $user['id'] === $dInfo[1];

	if (!$is_owner && $require_owner) {
		die_error("Error - ($filename) Not owner: " . strtoupper($d));
	}

	if ($_REQUEST['is_local_script'] !== 'true' || !$is_owner) {
		$keycode = $_REQUEST['keycode'];
		if ($keycode !== $dInfo[2]) {
			die_error("Error - ($filename) Invalid Server Key: " . strtoupper($d));
		}
	}

	if (empty($filename)) {
		return;
	}

	$stmt = $db->prepare('SELECT * FROM domain_files WHERE domain = ? AND filename = ?');
	$stmt->bind_param('is', $dInfo[0], $filename);
	$stmt->execute();
	$res = $stmt->get_result();
	$row = $res->fetch_assoc();

	if (!$is_owner) {
		if (empty($row)) {
			die_error("Error - ($filename) File not found: " . strtoupper($d), 404);
		}

		$fileheader = strtolower(explode("\r\n", $row['contents'], 2)[0]);
		if (substr($fileheader, 0, 6) !== 'public') {
			die_error("Error - ($filename) Private file: " . strtoupper($d), 403);
		}

		$fileheader_parts = explode(' ', $fileheader);
		if ($fileheader_parts[0] !== 'public') {
			die_error("Error - ($filename) Invalid file header: " . strtoupper($d), 403);
		}

		if (!in_array($opname, $fileheader_parts, true)) {
			die_error("Error - ($filename) Private operation: " . strtoupper($d), 403);
		}
	}

	if (empty($row)) {
		return array('id' => -1, 'filename' => $filename, 'contents' => '');
	}
	return $row;
}

function write_file($file_id, $filename, $contents) {
	global $db, $dInfo;
	if (strlen($contents) === 0) {
		if ($file_id < 0) {
			return;
		}
		$stmt = $db->prepare('DELETE FROM domain_files WHERE id = ?');
		$stmt->bind_param('i', $file_id);
	} else if ($file_id < 0) {
		$stmt = $db->prepare('INSERT INTO domain_files (domain, filename, contents) VALUES (?, ?, ?)');
		$stmt->bind_param('iss', $dInfo[0], $filename, $contents);
	} else {
		$stmt = $db->prepare('UPDATE domain_files SET contents = ? WHERE id = ?');
		$stmt->bind_param('si', $contents, $file_id);
	}

	$stmt->execute();
}

$fileserver = $_REQUEST['fileserver'];
if (!empty($fileserver)) {
	$file = verify_keycode($fileserver, 'fileserver');

	$maxlines = (int)$_REQUEST['maxlines'];
	$startline = (int)$_REQUEST['startline'];

	if ($startline <= 0) {
		$startline = 1;
	}

	if ($maxlines <= 0) {
		$maxlines = -1;
	}

	//now, get the lines that are required.
	$fdarray = explode("\r\n", $file['contents']);

	$endline = count($fdarray);
	if ($maxlines > 0) {
		$endline = ($startline - 1) + $maxlines;
	}

	for ($x = $startline - 1; $x < $endline && $x < count($fdarray); $x++) {
		echo $fdarray[$x] . "\r\n";
	}
	exit;
}

$write = $_REQUEST['write'];
if (!empty($write)) {
	$file = verify_keycode($write, 'write');
	$filedata = line_endings_to_dos($_REQUEST['filedata']);
	write_file($file['id'], $write, $filedata);
	exit;
}

$append = $_REQUEST['append'];
if (!empty($append)) {
	$file = verify_keycode($append, 'append');
	$filedata = $file['contents'] . line_endings_to_dos($_REQUEST['filedata']);
	write_file($file['id'], $append, $filedata);
	exit;
}

$safeappend = $_REQUEST['safeappend'];
if (!empty($safeappend)) {
	$file = verify_keycode($safeappend, 'safeappend');

	$filedata = $_REQUEST['filedata'];
	$idx = strpos($filedata, "\r");
	if ($idx !== false) {
		$filedata = substr($filedata, 0, $idx);
	}
	$idx = strpos($filedata, "\n");
	if ($idx !== false) {
		$filedata = substr($filedata, 0, $idx);
	}

	$filedata = $file['contents'];
	if (!empty($filedata) && substr($filedata, -2) !== "\r\n") {
		$filedata .= "\r\n";
	}

	$filedata = $filedata . $user['name'] . ':' . $filedata . "\r\n";
	write_file($file['id'], $append, $filedata);
	exit;
}


$delete = $_REQUEST['delete'];
if (!empty($delete)) {
	$file = verify_keycode($delete, 'delete', true);
	write_file($file['id'], $delete, '');
	exit;
}

$dir = $_REQUEST['dir'];
if (!empty($dir)) {
	verify_keycode('', 'dir', true);

	$stmt = $db->prepare('SELECT filename FROM domain_files WHERE domain = ?');
	$stmt->bind_param('is', $dInfo[0]);
	$stmt->execute();
	$res = $stmt->get_result();
	while ($row = $res->fetch_assoc()) {
		echo $row['filename'] . "\r\n";
	}
}

die_error('No action selected');
