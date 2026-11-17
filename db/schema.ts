import { sqliteTable, text, integer } from 'drizzle-orm/sqlite-core';
export const branches = sqliteTable('branches', {
  id: text('id').primaryKey(), name: text('name').notNull().unique(),
  code: text('code').notNull().unique(), active: integer('active').notNull().default(1),
  createdAt: text('created_at').notNull(),
});
export const members = sqliteTable('members', {
  id: text('id').primaryKey(), userId: text('user_id').unique(), email: text('email').notNull().unique(),
  username: text('username').unique(),
  permissions: text('permissions').notNull().default('{}'),
  name: text('name').notNull(), role: text('role').notNull(), branches: text('branches').notNull(), active: integer('active').notNull().default(1),
});
export const customers = sqliteTable('customers', {
  id: text('id').primaryKey(), name: text('name').notNull(), phone: text('phone').notNull(), address: text('address').notNull().default(''), createdAt: text('created_at').notNull(),
});
export const orders = sqliteTable('orders', {
  id: text('id').primaryKey(), branch: text('branch').notNull(), bill: text('bill').notNull().unique(), kind: text('kind').notNull(),
  customerId: text('customer_id'), customerName: text('customer_name').notNull(), phone: text('phone').notNull().default(''), address: text('address').notNull().default(''),
  lines: text('lines').notNull(), subtotal: integer('subtotal').notNull(), discount: integer('discount').notNull(), extra: integer('extra').notNull(),
  total: integer('total').notNull(), paid: integer('paid').notNull().default(0), notes: text('notes').notNull().default(''), coupon: text('coupon').notNull().default(''),
  cashier: text('cashier').notNull(), cashierId: text('cashier_id').notNull(), staff: text('staff').notNull().default(''), aggregator: text('aggregator').notNull().default(''),
  status: text('status').notNull().default('Ongoing'), createdAt: text('created_at').notNull(), updatedAt: text('updated_at').notNull(),
  dueDate: text('due_date').notNull().default(''), version: integer('version').notNull().default(0), bookingId: text('booking_id'), externalId: text('external_id').unique(),
  tailorId:text('tailor_id').references(()=>members.id), jobStatus:text('job_status').notNull().default('Pending'),
  assignedAt:text('assigned_at').notNull().default(''), jobUpdatedAt:text('job_updated_at').notNull().default(''),
  parentOrderId:text('parent_order_id'), documentType:text('document_type').notNull().default('invoice'),
  refundedTotal:integer('refunded_total').notNull().default(0), reason:text('reason').notNull().default(''),
  reasonCode:text('reason_code').notNull().default(''),
});
export const workItems = sqliteTable('work_items', {
  id:text('id').primaryKey(),orderId:text('order_id').notNull().references(()=>orders.id),
  lineIndex:integer('line_index').notNull(),quantity:integer('quantity').notNull(),
  tailorId:text('tailor_id').references(()=>members.id),status:text('status').notNull().default('Pending'),
  kind:text('kind').notNull().default('original'),parentTaskId:text('parent_task_id'),
  fault:text('fault').notNull().default(''),faultTailorId:text('fault_tailor_id'),
  reason:text('reason').notNull().default(''),approvedBy:text('approved_by'),approvedAt:text('approved_at').notNull().default(''),
  createdAt:text('created_at').notNull(),updatedAt:text('updated_at').notNull(),version:integer('version').notNull().default(0),
});
export const workCredits = sqliteTable('work_credits', {
  id:text('id').primaryKey(),taskId:text('task_id').notNull().references(()=>workItems.id),
  orderId:text('order_id').notNull().references(()=>orders.id),lineIndex:integer('line_index').notNull(),
  tailorId:text('tailor_id').notNull().references(()=>members.id),quantity:integer('quantity').notNull(),
  amount:integer('amount').notNull(),reason:text('reason').notNull(),createdAt:text('created_at').notNull(),
});
export const integrationEvents = sqliteTable('integration_events', {
  id:text('id').primaryKey(),orderId:text('order_id').notNull().references(()=>orders.id),
  branch:text('branch').notNull(),type:text('type').notNull(),payload:text('payload').notNull(),
  createdAt:text('created_at').notNull(),processedAt:text('processed_at').notNull().default(''),
});
export const payments = sqliteTable('payments', {
  id: text('id').primaryKey(), orderId: text('order_id').notNull().references(() => orders.id), branch: text('branch').notNull(),
  amount: integer('amount').notNull(), method: text('method').notNull(), reference: text('reference').notNull().default(''), actor: text('actor').notNull(), createdAt: text('created_at').notNull(),
});
export const expenses = sqliteTable('expenses', {
  id: text('id').primaryKey(), branch: text('branch').notNull(), category: text('category').notNull(), description: text('description').notNull(),
  amount: integer('amount').notNull(), method: text('method').notNull(), actor: text('actor').notNull(), createdAt: text('created_at').notNull(),
});
export const audit = sqliteTable('audit', {
  id: text('id').primaryKey(), branch: text('branch').notNull(), actor: text('actor').notNull(), action: text('action').notNull(), entity: text('entity').notNull(), detail: text('detail').notNull(), createdAt: text('created_at').notNull(),
});
export const prices = sqliteTable('prices', {id: text('id').primaryKey(), price: integer('price').notNull(), active: integer('active').notNull().default(1)});
export const jobEvents=sqliteTable('job_events',{
  id:text('id').primaryKey(),orderId:text('order_id').notNull().references(()=>orders.id),branch:text('branch').notNull(),
  actor:text('actor').notNull(),actorName:text('actor_name').notNull(),action:text('action').notNull(),detail:text('detail').notNull(),createdAt:text('created_at').notNull(),
});
export const attachments = sqliteTable('attachments', {
  id: text('id').primaryKey(), branch: text('branch').notNull(), orderId: text('order_id'), name: text('name').notNull(), type: text('type').notNull(), objectKey: text('object_key').notNull(), createdAt: text('created_at').notNull(),
});
export const notifications = sqliteTable('notifications', {
  id:text('id').primaryKey(), memberId:text('member_id').notNull().references(()=>members.id),
  orderId:text('order_id').notNull().references(()=>orders.id), branch:text('branch').notNull(),
  type:text('type').notNull(),title:text('title').notNull(),message:text('message').notNull(),
  taskId:text('task_id'),
  createdAt:text('created_at').notNull(),readAt:text('read_at').notNull().default(''),
});
export const pushSubscriptions = sqliteTable('push_subscriptions', {
  id:text('id').primaryKey(),memberId:text('member_id').notNull().references(()=>members.id),
  subscription:text('subscription').notNull(),createdAt:text('created_at').notNull(),
});
export const pushDeliveries = sqliteTable('push_deliveries', {
  id:text('id').primaryKey(),notificationId:text('notification_id').notNull().references(()=>notifications.id),
  subscriptionId:text('subscription_id').notNull().references(()=>pushSubscriptions.id),
  attempts:integer('attempts').notNull().default(0),nextAttempt:text('next_attempt').notNull().default(''),
  sentAt:text('sent_at').notNull().default(''),
});
export const staffShiftPolicies = sqliteTable('staff_shift_policies', {
  memberId:text('member_id').primaryKey().references(()=>members.id),
  enabled:integer('enabled').notNull().default(0),weekly:text('weekly').notNull().default('[]'),
  exceptions:text('exceptions').notNull().default('[]'),revision:integer('revision').notNull().default(0),
  updatedBy:text('updated_by').notNull(),updatedAt:text('updated_at').notNull(),
});
export const securityAlerts = sqliteTable('security_alerts', {
  id:text('id').primaryKey(),memberId:text('member_id').notNull().references(()=>members.id),
  staffName:text('staff_name').notNull(),username:text('username').notNull(),
  source:text('source').notNull(),reason:text('reason').notNull(),attemptedBranch:text('attempted_branch').notNull().default(''),
  firstAt:text('first_at').notNull(),lastAt:text('last_at').notNull(),attempts:integer('attempts').notNull().default(1),
  path:text('path').notNull().default(''),userAgent:text('user_agent').notNull().default(''),
});
export const securityAlertReceipts = sqliteTable('security_alert_receipts', {
  id:text('id').primaryKey(),alertId:text('alert_id').notNull().references(()=>securityAlerts.id),
  memberId:text('member_id').notNull().references(()=>members.id),readAt:text('read_at').notNull(),
});
export const securityPushDeliveries = sqliteTable('security_push_deliveries', {
  id:text('id').primaryKey(),alertId:text('alert_id').notNull().references(()=>securityAlerts.id),
  subscriptionId:text('subscription_id').notNull().references(()=>pushSubscriptions.id),
  attempts:integer('attempts').notNull().default(0),nextAttempt:text('next_attempt').notNull().default(''),sentAt:text('sent_at').notNull().default(''),
});
