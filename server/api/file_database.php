<?

$rewrite_done = true;
require_once('function.php');

$returnwith = (string)(int)$_REQUEST['returnwith'];
if ($returnwith === '0') {
	$returnwith = '2000';
}

echo $returnwith;

$getfile = $_REQUEST['getfile'];
if (!empty($getfile)){
    $stmt = $db->prepare('SELECT filename, filedata FROM file_database WHERE id = ? AND deleted = 0 AND ver = ?');
    $stmt->bind_param('ii', $getfile, $ver);
    $stmt->execute();
    $res = $stmt->get_result();
    $row = $res->fetch_array();
    if (empty($row)) {
        die_error('File not found.', 404);
    }

    echo $row['filename'];
    echo ':';
    die($row['filedata']);
}


$removenow = $_REQUEST['removenow'];
if (!empty($removenow)){
    $stmt = $db->prepare('UPDATE file_database SET deleted = 1 WHERE id = ? AND owner = ? AND ver = ?');
    $stmt->bind_param('iii', $removenow, $user['id'], $ver);
    $stmt->execute();
    die("File ID $removenow was removed.");
}


$getforremoval = $_REQUEST['getforremoval'];
if (!empty($getforremoval)){
    $stmt = $db->prepare('SELECT id, title, version, createtime FROM file_database WHERE owner = ? AND deleted = 0 AND ver = ?');
    $stmt->bind_param('ii', $user['id'], $ver);
    $stmt->execute();
    $res = $stmt->get_result();

    while($row = $res->fetch_array()) {
        echo $row['id'] . ': ' . $row['title'] . '(version ' . $row['version'] . ') ' . date('d.m.Y', $row['createtime'])  . ':--:';
    }

    exit;
}

$getcategory = $_REQUEST['getcategory'];
if (!empty($getcategory)){
    $stmt = $db->prepare('SELECT id, title, version, owner, LENGTH(filedata) AS filesize, description, createtime, filename FROM file_database WHERE category = ? AND deleted = 0 AND ver = ?');
    $stmt->bind_param('si', $getcategory, $ver);
    $stmt->execute();
    $res = $stmt->get_result();
    while($row = $res->fetch_array()) {
        $time = $row['createtime'];
        echo $row['id'].":--:".$row['title'].":--:".$row['version'].":--:".$row['filesize'].":--:".$row['owner'].":--:".$row['filename'].":--:".$row['$description'].":--:".date('d.m.Y', $time).":--:".date('H:i:s', $time).":--:--:";
    }
    exit;
}

$shortfilename = $_REQUEST['shortfilename'];
if (!empty($shortfilename)){
    if (strpos($shortfilename, '/') !== false || strpos($shortfilename, '\\') !== false || strpos($shortfilename, ':') !== false) {
        die_error('Invalid filename.', 400);
    }

    $timestamp = time();
    $aip = $_SERVER['REMOTE_ADDR'];
    $stmt = $db->prepare('INSERT INTO file_database (filename, filedata, version, title, description, category, createtime, ip, deleted, owner, ver) VALUES (?,?,?,?,?,?,?,?,0,?,?)');
    $stmt->bind_param('ssssssisii', $shortfilename, $_REQUEST['filedata'], $_REQUEST['version'], $_REQUEST['title'], $_REQUEST['description'], $_REQUEST['category'], $timestamp, $aip, $user['id'], $ver);
    $stmt->execute();

    die("Upload complete!");
}

die_error('Invalid request.', 400);
