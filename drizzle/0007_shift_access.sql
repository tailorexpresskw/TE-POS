CREATE TABLE `security_alert_receipts` (
	`id` text PRIMARY KEY NOT NULL,
	`alert_id` text NOT NULL,
	`member_id` text NOT NULL,
	`read_at` text NOT NULL,
	FOREIGN KEY (`alert_id`) REFERENCES `security_alerts`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`member_id`) REFERENCES `members`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `security_alerts` (
	`id` text PRIMARY KEY NOT NULL,
	`member_id` text NOT NULL,
	`staff_name` text NOT NULL,
	`username` text NOT NULL,
	`source` text NOT NULL,
	`reason` text NOT NULL,
	`attempted_branch` text DEFAULT '' NOT NULL,
	`first_at` text NOT NULL,
	`last_at` text NOT NULL,
	`attempts` integer DEFAULT 1 NOT NULL,
	`path` text DEFAULT '' NOT NULL,
	`user_agent` text DEFAULT '' NOT NULL,
	FOREIGN KEY (`member_id`) REFERENCES `members`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `security_push_deliveries` (
	`id` text PRIMARY KEY NOT NULL,
	`alert_id` text NOT NULL,
	`subscription_id` text NOT NULL,
	`attempts` integer DEFAULT 0 NOT NULL,
	`next_attempt` text DEFAULT '' NOT NULL,
	`sent_at` text DEFAULT '' NOT NULL,
	FOREIGN KEY (`alert_id`) REFERENCES `security_alerts`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`subscription_id`) REFERENCES `push_subscriptions`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `staff_shift_policies` (
	`member_id` text PRIMARY KEY NOT NULL,
	`enabled` integer DEFAULT 0 NOT NULL,
	`weekly` text DEFAULT '[]' NOT NULL,
	`exceptions` text DEFAULT '[]' NOT NULL,
	`revision` integer DEFAULT 0 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	FOREIGN KEY (`member_id`) REFERENCES `members`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX security_alerts_first_at ON security_alerts(first_at);
CREATE INDEX security_alerts_member_time ON security_alerts(member_id,last_at);
CREATE INDEX security_receipts_member ON security_alert_receipts(member_id,alert_id);
CREATE INDEX security_push_subscription ON security_push_deliveries(subscription_id);
