ALTER TABLE `members` ADD `username` text;--> statement-breakpoint
CREATE UNIQUE INDEX `members_username_unique` ON `members` (`username`);