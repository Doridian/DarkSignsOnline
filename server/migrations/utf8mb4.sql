-- One-off repair for text the PHP server stored double-encoded.
--
-- The tables have always been utf8mb4, but PHP's mysqli talked to the
-- database in whatever character set the server announced, and MariaDB
-- before 11.6 announces latin1. So the UTF-8 a client sent was read as
-- latin1 and converted *again* on the way into a utf8mb4 column: `ü` went in
-- as the two bytes C3 BC, was taken for the two characters `Ã¼`, and stored
-- as four. PHP read it back through the same latin1 connection, so it never
-- noticed. The Rust server talks utf8mb4 and would show `Ã¼`.
--
-- Whether a database needs this depends on the server it ran against:
-- `SELECT @@character_set_server` saying latin1 means it almost certainly
-- does. To see what it would change in one table first:
--
--   SELECT id, message, CONVERT(CAST(CONVERT(message USING latin1) AS BINARY) USING utf8mb4)
--     FROM chat
--    WHERE CAST(message AS BINARY) REGEXP '[\\x80-\\xFF]'
--      AND CAST(CONVERT(CONVERT(message USING latin1) USING utf8mb4) AS BINARY) = CAST(message AS BINARY)
--      AND CAST(CONVERT(CAST(CONVERT(message USING latin1) AS BINARY) USING utf8mb4) AS BINARY)
--          = CAST(CONVERT(message USING latin1) AS BINARY);
--
-- Each column is repaired only where the repair is lossless: the text has
-- to fit in latin1 (so it was not stored correctly in the first place, as
-- an emoji would be) and its latin1 bytes have to be valid UTF-8 (so it
-- really was double-encoded, and is not a genuine `é` that happens to be
-- latin1-representable). Rows that are already right are left alone, which
-- makes it safe to run twice.
--
-- Run it once, with the server stopped:
--
--   mariadb --default-character-set=utf8mb4 darksignsonline < utf8mb4.sql

SET NAMES utf8mb4;
-- Not strict: text that does not fit in latin1 has to come out of the
-- conversion as `?` and fail the comparison, rather than abort the update.
SET SESSION sql_mode = '';
START TRANSACTION;

UPDATE `users` SET `username` = CONVERT(CAST(CONVERT(`username` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`username` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`username` USING latin1) USING utf8mb4) AS BINARY) = CAST(`username` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`username` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`username` USING latin1) AS BINARY);

UPDATE `users` SET `email` = CONVERT(CAST(CONVERT(`email` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`email` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`email` USING latin1) USING utf8mb4) AS BINARY) = CAST(`email` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`email` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`email` USING latin1) AS BINARY);

UPDATE `domains` SET `host` = CONVERT(CAST(CONVERT(`host` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`host` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`host` USING latin1) USING utf8mb4) AS BINARY) = CAST(`host` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`host` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`host` USING latin1) AS BINARY);

UPDATE `domain_files` SET `filename` = CONVERT(CAST(CONVERT(`filename` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`filename` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`filename` USING latin1) USING utf8mb4) AS BINARY) = CAST(`filename` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`filename` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`filename` USING latin1) AS BINARY);

UPDATE `domain_files` SET `contents` = CONVERT(CAST(CONVERT(`contents` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`contents` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`contents` USING latin1) USING utf8mb4) AS BINARY) = CAST(`contents` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`contents` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`contents` USING latin1) AS BINARY);

UPDATE `domain_scripts` SET `code` = CONVERT(CAST(CONVERT(`code` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`code` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`code` USING latin1) USING utf8mb4) AS BINARY) = CAST(`code` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`code` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`code` USING latin1) AS BINARY);

UPDATE `dsmail` SET `from_addr` = CONVERT(CAST(CONVERT(`from_addr` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`from_addr` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`from_addr` USING latin1) USING utf8mb4) AS BINARY) = CAST(`from_addr` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`from_addr` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`from_addr` USING latin1) AS BINARY);

UPDATE `dsmail` SET `subject` = CONVERT(CAST(CONVERT(`subject` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`subject` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`subject` USING latin1) USING utf8mb4) AS BINARY) = CAST(`subject` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`subject` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`subject` USING latin1) AS BINARY);

UPDATE `dsmail` SET `message` = CONVERT(CAST(CONVERT(`message` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`message` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`message` USING latin1) USING utf8mb4) AS BINARY) = CAST(`message` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`message` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`message` USING latin1) AS BINARY);

UPDATE `chat` SET `message` = CONVERT(CAST(CONVERT(`message` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`message` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`message` USING latin1) USING utf8mb4) AS BINARY) = CAST(`message` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`message` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`message` USING latin1) AS BINARY);

UPDATE `file_database` SET `filename` = CONVERT(CAST(CONVERT(`filename` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`filename` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`filename` USING latin1) USING utf8mb4) AS BINARY) = CAST(`filename` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`filename` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`filename` USING latin1) AS BINARY);

UPDATE `file_database` SET `version` = CONVERT(CAST(CONVERT(`version` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`version` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`version` USING latin1) USING utf8mb4) AS BINARY) = CAST(`version` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`version` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`version` USING latin1) AS BINARY);

UPDATE `file_database` SET `title` = CONVERT(CAST(CONVERT(`title` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`title` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`title` USING latin1) USING utf8mb4) AS BINARY) = CAST(`title` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`title` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`title` USING latin1) AS BINARY);

UPDATE `file_database` SET `description` = CONVERT(CAST(CONVERT(`description` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`description` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`description` USING latin1) USING utf8mb4) AS BINARY) = CAST(`description` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`description` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`description` USING latin1) AS BINARY);

UPDATE `file_database` SET `category` = CONVERT(CAST(CONVERT(`category` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`category` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`category` USING latin1) USING utf8mb4) AS BINARY) = CAST(`category` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`category` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`category` USING latin1) AS BINARY);

UPDATE `file_database` SET `filedata` = CONVERT(CAST(CONVERT(`filedata` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`filedata` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`filedata` USING latin1) USING utf8mb4) AS BINARY) = CAST(`filedata` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`filedata` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`filedata` USING latin1) AS BINARY);

UPDATE `libraries` SET `data` = CONVERT(CAST(CONVERT(`data` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`data` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`data` USING latin1) USING utf8mb4) AS BINARY) = CAST(`data` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`data` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`data` USING latin1) AS BINARY);

UPDATE `textspace` SET `text` = CONVERT(CAST(CONVERT(`text` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`text` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`text` USING latin1) USING utf8mb4) AS BINARY) = CAST(`text` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`text` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`text` USING latin1) AS BINARY);

UPDATE `transactions` SET `description` = CONVERT(CAST(CONVERT(`description` USING latin1) AS BINARY) USING utf8mb4)
  WHERE CAST(`description` AS BINARY) REGEXP '[\\x80-\\xFF]'
    AND CAST(CONVERT(CONVERT(`description` USING latin1) USING utf8mb4) AS BINARY) = CAST(`description` AS BINARY)
    AND CAST(CONVERT(CAST(CONVERT(`description` USING latin1) AS BINARY) USING utf8mb4) AS BINARY) = CAST(CONVERT(`description` USING latin1) AS BINARY);

COMMIT;
