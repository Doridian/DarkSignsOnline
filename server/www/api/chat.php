<?php

require_once('function.php');

// Chat, which the original client got from IRC. A browser has no raw
// sockets, so the room lives here instead: one table, one endpoint, and a
// client that asks for whatever is newer than the last line it holds. That
// is the same incremental shape `dsmail.php` uses, for the same reason --
// the client keeps its own copy and only ever fetches the tail.
//
// Unlike `dsmail.php` this speaks protocol 2 throughout: no four-character
// status code in front of the body, so nothing has to be stripped off.

/** How many lines a client with nothing yet is given as backlog. */
define('CHAT_BACKLOG', 100);

/** The most a single fetch will hand back, however far behind the caller is. */
define('CHAT_MAX_FETCH', 500);

/** A chat line is one line, and not a long one. */
define('CHAT_MAX_LENGTH', 1024);

// A loose limit, meant for a stuck script rather than for a determined
// flooder: `ChatSend` is a scripting function, so a loop calling it is the
// ordinary accident this guards against.
define('CHAT_RATE_SECONDS', 10);
define('CHAT_RATE_LIMIT', 10);

/**
 * Reduce a message to the one line it is allowed to be.
 *
 * Newlines would break the record format, and the other control characters
 * are what the terminal renderer would otherwise have to defend against.
 */
function chat_clean($msg) {
    $msg = preg_replace('/[\x00-\x1F\x7F]+/u', ' ', $msg);
    if ($msg === null) {
        // Not valid UTF-8, so the /u pass gave up. Fall back to bytes.
        $msg = preg_replace('/[\x00-\x1F\x7F]+/', ' ', $msg);
    }
    $msg = trim($msg);
    if (mb_strlen($msg) > CHAT_MAX_LENGTH) {
        $msg = mb_substr($msg, 0, CHAT_MAX_LENGTH);
    }
    return $msg;
}

/** One record, in the `:--:` format the rest of the API uses. */
function chat_record($row) {
    return 'X_' . $row['id']
        . ':--:' . $row['username']
        . ':--:' . ($row['action'] ? '1' : '0')
        . ':--:' . dso_b64_encode($row['message'])
        . ':--:' . date('d.m.Y H:i:s', $row['time'])
        . "\r\n";
}

$action = $_REQUEST['action'] ?? '';

if ($action === 'read') {
    $last = (int)($_REQUEST['last'] ?? 0);

    if ($last > 0) {
        // Caught up already, or nearly: everything newer, oldest first.
        $limit = CHAT_MAX_FETCH;
        $stmt = $db->prepare(
            'SELECT c.id, c.action, c.message, c.time, u.username
             FROM chat c JOIN users u ON u.id = c.user
             WHERE c.id > ? ORDER BY c.id ASC LIMIT ?'
        );
        $stmt->bind_param('ii', $last, $limit);
        $stmt->execute();
        $result = $stmt->get_result();
        while ($row = $result->fetch_assoc()) {
            echo chat_record($row);
        }
        exit;
    }

    // Nothing held yet, so this is the backlog a client opens with. It has to
    // be taken newest-first to get the *last* hundred rather than the first,
    // and then turned back around so the client still receives them in the
    // order they were said.
    $limit = CHAT_BACKLOG;
    $stmt = $db->prepare(
        'SELECT c.id, c.action, c.message, c.time, u.username
         FROM chat c JOIN users u ON u.id = c.user
         ORDER BY c.id DESC LIMIT ?'
    );
    $stmt->bind_param('i', $limit);
    $stmt->execute();
    $result = $stmt->get_result();
    $rows = [];
    while ($row = $result->fetch_assoc()) {
        $rows[] = $row;
    }
    foreach (array_reverse($rows) as $row) {
        echo chat_record($row);
    }
    exit;
}

if ($action === 'send') {
    $msg = chat_clean($_REQUEST['message'] ?? '');
    if ($msg === '') {
        die_error('Nothing to say.');
    }

    // `/me`, which the original sent as a CTCP ACTION. Here it is a flag on
    // the row, so the client does not have to know what CTCP was.
    $is_action = !empty($_REQUEST['emote']) ? 1 : 0;

    $since = time() - CHAT_RATE_SECONDS;
    $stmt = $db->prepare('SELECT COUNT(*) FROM chat WHERE user = ? AND time > ?');
    $stmt->bind_param('ii', $user['id'], $since);
    $stmt->execute();
    $recent = (int)$stmt->get_result()->fetch_row()[0];
    if ($recent >= CHAT_RATE_LIMIT) {
        die_error('You are talking too fast.', 429);
    }

    $time = time();
    $stmt = $db->prepare('INSERT INTO chat (user, action, message, time) VALUES (?, ?, ?, ?)');
    $stmt->bind_param('iisi', $user['id'], $is_action, $msg, $time);
    $stmt->execute();

    // The id the line got, so a sender knows which of the lines it is about
    // to read back is its own.
    die('X_' . $db->insert_id);
}

die_error('No request sent');
