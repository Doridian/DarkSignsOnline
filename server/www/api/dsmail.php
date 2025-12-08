<?php

require_once('function.php');

print_returnwith('7000', -1);

function filter_subject($subj) {
    $idx = strpos($subj, "\r");
    if ($idx !== false) {
        $subj = substr($subj, 0, $idx);
    }
    $idx = strpos($subj, "\n");
    if ($idx !== false) {
        $subj = substr($subj, 0, $idx);
    }
    return $subj;
}

$action = $_REQUEST['action'];
if ($action === 'inbox')
{
    $last = (int)$_REQUEST['last'];
    $stmt = $db->prepare('SELECT id, from_addr, subject, message, time FROM dsmail WHERE to_user = ? AND id > ? ORDER BY id ASC');
    $stmt->bind_param('ii', $user['id'], $last);
    $stmt->execute();
    $result = $stmt->get_result();
    while ($mail = $result->fetch_assoc())
    {
        echo 'X_'.$mail['id'].':--:'.$mail['from_addr'].':--:'.dso_b64_encode($mail['subject']).':--:'.dso_b64_encode($mail['message']).':--:'.date('d.m.Y H:i:s', $mail['time'])."\r\n";
    }
    exit;
}
else if ($action === 'send')
{
    $to = $_REQUEST['to'];
    $sub = filter_subject($_REQUEST['subject']);
    $msg = $_REQUEST['message'];
    $toArr = explode(',', $to);
    
    if (sizeof($toArr) > 10)
    {
        die('Cant send mail to more than 10 people.');
    }
    
    $nameID = [];
    foreach ($toArr as $name)
    {
        $tmpID = userToId($name);
        if ($tmpID === -1)
        {
            die('Unknown name: '.$name);
        }
        array_push($nameID, $tmpID);
    }

    $time = time();

    $msg_hash = dso_hash($message);
    $uEmail = $user['username'] . '@users';
    foreach ($nameID AS $id)
    {
        $stmt = $db->prepare("INSERT INTO dsmail (from_addr, to_user, subject, message, time, message_hash) VALUES (?, ?, ?, ?, ?, ?)");
        $stmt->bind_param('sissis', $uEmail, $id, $sub, $msg, $time, $msg_hash);
        $stmt->execute();
    }
    die('success');
}
else if ($action === 'script_send_to_self')
{
    $server = $_REQUEST['server'];
    if (empty($server)) {
        $server = $user['username'] . '.usr';
    }
    $sInfo = getDomainInfo($server);
    if ($sInfo === false) {
        die_error('Invalid server');
    }
    
    $from = $_REQUEST['from'];
    $to = $user['id'];
    $subject = filter_subject($_REQUEST['subject']);
    $message = $_REQUEST['message'];

    $emlsplit = explode('@', $from);
    if (sizeof($emlsplit) !== 2) {
        die_error('Invalid email');
    }

    $dInfo = getDomainInfo($emlsplit[1]);
    if ($dInfo === false || $dInfo['owner'] !== $sInfo['owner']) {
        die_error('Server owner not matched (' . $emlsplit[1] . ' vs ' . $server . ')');
    }

    if (preg_match('/[^a-zA-Z0-9_-]/', $emlsplit[0]) || strlen($emlsplit[0]) > 32) {
        die_error('Invalid from name');
    }

    $msg_hash = dso_hash($message);
    $time = time();
    $stmt = $db->prepare("REPLACE INTO dsmail (from_addr, to_user, subject, message, message_hash, time) VALUES (?, ?, ?, ?, ?, ?)");
    $stmt->bind_param('sisssi', $from, $to, $subject, $message, $msg_hash, $time);
    $stmt->execute();
    die('OK');
}
die_error('No request sent');
