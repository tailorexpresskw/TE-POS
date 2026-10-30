import { sqliteTable, text, integer } from 'drizzle-orm/sqlite-core';
export const members = sqliteTable('members', {
  id: text('id').primaryKey(), userId: text('user_id').unique(), email: text('email').notNull().unique(),
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
export const attachments = sqliteTable('attachments', {
  id: text('id').primaryKey(), branch: text('branch').notNull(), orderId: text('order_id'), name: text('name').notNull(), type: text('type').notNull(), objectKey: text('object_key').notNull(), createdAt: text('created_at').notNull(),
});
