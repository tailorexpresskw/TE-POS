# Service work, reception checks and linked invoices

## Assign services or an invoice

From Tracking, Sales List or the receipt, choose Assign tailor. An invoice with several service lines offers a service selector: leave all selected for the whole invoice, or select individual lines and assign them to a branch tailor. Quantities on a service line stay together. Use separate invoice lines for garments that need different instructions or different tailors. Tailors see only their own service lines and never invoice amounts, payments or customer contact details.

Started work needs a reason to be reassigned. Approved work is retained in history and is corrected through a backjob. Existing invoices migrate into service work records; existing completed work remains completed with a legacy-history label.

## Reception checks

Tailors move work through Pending, In Progress, On Hold and Awaiting Review. Awaiting Review means the tailor has submitted the work; it does not mean it is approved. Reception opens Job details and chooses Check finished work, then approves or returns the service with correction instructions. Admin can also perform a recorded reception check when necessary. Managers and Supervisors cannot bypass the check by changing a work status.

An invoice becomes completed only when all its active services, including backjobs, are approved. Prepared, Packed and subsequent delivery statuses are blocked until that approval. Work progress and delivery status remain separate, so reception still controls the handover workflow.

## Backjobs and credit

Reception or Admin creates a backjob from the latest approved service, records a reason, chooses a quantity and assigns the fixing tailor. The invoice reopens to Ongoing, and the backjob goes through the same reception check.

- Previous tailor fault: when the correction is approved, debit the previous tailor's credit for the affected quantity and credit the fixing tailor.
- No tailor fault: retain the previous credit and also credit the fixing tailor when the correction is approved.

Credit is a work-performance value, not an automatic salary or commission payment. It uses the service value after invoice discount, in integer fils, and excludes extra charges. Credit entries and reversals remain in a ledger. A no-fault backjob can make credited work exceed invoice sales; sales revenue is recorded once. A financial refund does not erase work already performed or its approval history. Refund-related disciplinary or payroll rules would be a separate policy.

## Refund and cancellation permissions

Only Admin grants Allow refunds and Allow cancellations in each staff account. These permissions apply to assigned branches and can be revoked without waiting for a new login. Non-Admin accounts have neither grant by default. A paid cancellation requires both grants because it also returns a payment.

Refund services / invoice offers original service quantities that have not already been credited. Choose quantities or Refund whole invoice. A full refund includes the selected invoice's remaining extra charges. Delivery and other charge sub-invoices have their own balances and are refunded separately.

Every refund creates a numbered refund credit note linked to the original. Original service prices, quantity, discount and total stay intact. The original records accumulated credit, remaining payment and current balance. Refunded quantities cannot be refunded again. The server calculates discount rounding, rejects excess refunds and protects concurrent updates. Cash-return entries record payments made externally; this app does not transfer money. A credit-only adjustment is possible only when the remaining collected payment does not exceed the new invoice total; otherwise return the excess payment.

Cancellation requires a category and explanation and creates a linked cancellation note. Paid amounts must be returned externally. Original records and audit history are retained. Cancellation of a main invoice does not automatically cancel separately issued delivery sub-invoices.

## Additional charges and printing

Add delivery / extra charge on an original receipt creates a numbered charge sub-invoice. It can be paid immediately or collected later and appears under Linked documents. It does not rewrite the main invoice's total. Select Charge type Delivery for a delivery invoice; its Send delivery request action collects address and phone and keeps a local draft until Reception approves. Sending creates a Ready request in inventory automatically. Other extra charges do not dispatch.

Customer receipts use the existing 80 mm paper format. WhatsApp PDFs retain the separate phone-friendly layout. Refund, cancellation and charge documents identify their purpose and original invoice. Print tailor work slips groups current work by tailor with service quantities, garment notes and backjob instructions; these slips exclude invoice amounts and customer phone numbers. Review the preview before printing. The app cannot verify that a physical printer produced a page, and WhatsApp attachments and sending remain manual.

## Phone dashboard and notifications

Manager, Supervisor and Admin dashboards include reception-check, backjob, refund and cancellation cards plus approved tailor work credit for the selected dates. Branch tables become cards on phone screens. Sales and balances reflect accumulated credits against invoices in the selected invoice dates; payment and cash-return reports use payment dates. Work credit uses approval/adjustment dates.

Assignment alerts go to the assigned tailor. Review alerts go to branch office staff. Management receives backjob, refund, cancellation, approved-work and hold alerts within branch access. Lock-screen push text stays generic. In-app alerts remain available when device notifications are unsupported or permission is denied. Actual background delivery still depends on HTTPS, a running server and browser/device permission.

## Future AI, storage and home-service connections

No AI, inventory or home-service connector is enabled by this change. Existing invoice IDs, branch IDs, catalogue service IDs and parent-document links remain stable. Each new invoice or workflow mutation also records an integration_events outbox entry in the same database transaction. A future authenticated adapter can process these durable events, use its own deduplication keys and map external booking/storage IDs without putting credentials in the Flutter app.

GET /api/orders/{id}/customer-status provides a staff-authenticated, branch-checked status summary without tailor blame, internal backjob reasons, prices or phone numbers. A future customer-response tool still needs a dedicated authentication/authorization design and verified customer ownership before using it. There is no new anonymous order lookup or automatic customer messaging endpoint.

Run one server instance with persistent storage. Keep all migrations, back up the database and documents, and test printers and staff permissions before using the new workflows in branches.
