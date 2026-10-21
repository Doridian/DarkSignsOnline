-- The world every parity run starts from. Passwords are the username
-- followed by "pass", hashed by PHP at cost 4 to keep the run quick.

INSERT INTO users (id, username, password, active, email, createtime, ip, lastseen, emailverifycode, cash) VALUES
  (1, 'alice', '$2y$04$aSr2LtaKgx60l8wyxaffWOTDVz8kzXR77By7H8OsBarB0yhzE/TjC', 1, 'alice@example.com', 1700000000, '10.1.1.1', 1700000000, '', 5000),
  (2, 'bob', '$2y$04$B6gzwjSnfLFGSvN38sM3u.tc1iRan624x2F8H6noRGhZ67twkrzY6', 1, 'bob@example.com', 1700000000, '10.1.1.2', 1700000000, '', 50),
  (3, 'carol', '$2y$04$pGNlesqrJEjhwh5J41Kz5OkS4SYrtlHLSJPXDgnl.2TsIjrGgMBLC', 0, 'carol@example.com', 1700000000, '10.1.1.3', 1700000000, 'CarolVerifyCode1', 200),
  (4, 'dave', '$2y$04$vfdJfMHShkc6u0nJ4ojZr..v6jHzhuCSTcFSpRaQKBB.2ZYsOHkWG', 1, 'dave@example.com', 1700000000, '10.1.1.4', 1700000000, '', 0),
  (42, 'bank', '$2y$04$qJuV.tSoh135OHq4e2QwAe72ZArJTIBmhvtdvXcMuVhosdAiVSxby', 1, 'bank@example.com', 1700000000, '10.1.1.42', 1700000000, '', 1000000);

INSERT INTO domains (id, owner, ip, host, regtype, time, keycode, parent) VALUES
  (1, 1, '11.0.0.1', 'alice.usr', 'DOMAIN', 1700000001, 'AliceUsrKeycode1', NULL),
  (2, 2, '11.0.0.2', 'bob.usr', 'DOMAIN', 1700000002, 'BobUsrKeycode001', NULL),
  (3, 1, '11.0.1.1', 'alice.com', 'DOMAIN', 1700000003, 'AliceComKeycode1', NULL),
  (4, 1, '11.0.1.2', 'www.alice.com', 'SUBDOMAIN', 1700000004, 'AliceWwwKeycode1', 3),
  (5, 1, '11.9.9.9', NULL, 'IP', 1700000005, 'AliceIpKeycode01', NULL),
  (6, 2, '11.0.2.1', 'bob.net', 'DOMAIN', 1700000006, 'BobNetKeycode001', NULL),
  (7, 4, '11.0.0.4', 'dave.usr', 'DOMAIN', 1700000007, 'DaveUsrKeycode01', NULL),
  -- A `$1` in the name and a digit leading the key: the version 1 rewrite
  -- feeds both to preg_replace as a replacement, where `$17` is a group.
  (8, 1, '11.0.3.1', 'pay$1.org', 'DOMAIN', 1700000008, '7DollarKeycode01', NULL);

INSERT INTO domain_scripts (id, domain, port, code, ip, time, ver) VALUES
  (1, 3, 80, 'say "hello"\r\nx = FileServer("log.txt")\r\n  server write log.txt hi\r\nSERVER APPEND log.txt more\r\nSERVER DELETE log.txt', '10.1.1.1', 1700000010, 1),
  (2, 3, 80, 'Sub Main\r\n  Say "v2 hello"\r\nEnd Sub', '10.1.1.1', 1700000011, 2),
  (3, 3, 81, 'Option DSciptCompiled\r\nZW5jcnlwdGVk', '10.1.1.1', 1700000012, 2),
  (4, 6, 22, 'Say "bob v1"', '10.1.1.2', 1700000013, 1),
  (5, 5, 1, 'Say "ip host"', '10.1.1.1', 1700000014, 2);

INSERT INTO domain_files (id, domain, filename, contents) VALUES
  (1, 3, 'public.txt', 'Public file\r\nline two\r\nline three\r\nline four'),
  (2, 3, 'allow.txt', 'allowlist = fileserver, safeappend\r\nfirst'),
  (3, 3, 'private.txt', 'just a secret\r\nhidden'),
  (4, 3, 'zero.txt', '0'),
  (5, 6, 'bobs.txt', 'public\r\nbob was here');

INSERT INTO dsmail (id, to_user, from_addr, subject, message, time, message_hash) VALUES
  (1, 1, 'bob@users', 'Hello', 'Hi alice\r\nhow are you?', 1700000100, 'h1'),
  (2, 1, 'admin@darksigns.com', 'Mission', 'Ünïcode body ✓', 1700000200, 'h2'),
  (3, 2, 'alice@users', 'For bob', 'bob only', 1700000300, 'h3');

INSERT INTO chat (id, user, action, message, time) VALUES
  (1, 1, 0, 'hello room', 1700000400),
  (2, 2, 1, 'waves', 1700000401),
  (3, 1, 0, 'ünïcode ✓', 1700000402);

INSERT INTO file_database (id, owner, filename, version, title, description, createtime, ip, deleted, category, ver, filedata) VALUES
  (1, 1, 'snake.ds', '1.0', 'Snake', 'A game', 1700000500, '10.1.1.1', 0, 'Games', 1, 'Say "snake"'),
  (2, 2, 'scan.ds', '2.1', 'Scanner', 'Scans ✓ things', 1700000600, '10.1.1.2', 0, 'Tools (Hacking)', 1, 'Say "scän"'),
  (3, 1, 'old.ds', '0.1', 'Old', 'Gone', 1700000700, '10.1.1.1', 1, 'Games', 1, 'deleted'),
  (4, 1, 'snake2.ds', '1.0', 'Snake 2', 'v2 only', 1700000800, '10.1.1.1', 0, 'Games', 2, 'Say "snake2"');

INSERT INTO libraries (id, hash, data, owner, time) VALUES
  (1, 'a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447', 'hello world\n', 1, 1700000900);

INSERT INTO textspace (id, chan, owner, lastupdate, text, deleted) VALUES
  (1, 5, 1, 1700001000, 'first text', 0),
  (2, 5, 2, 1700001001, 'second text', 0);

INSERT INTO email_codes (id, user, code, expiry, action) VALUES
  (1, 2, 'BobResetCode0001', 1999999999, 'forgot_password'),
  (2, 2, 'BobExpiredCode01', 1700000000, 'forgot_password');
