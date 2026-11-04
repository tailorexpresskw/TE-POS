part of 'app.dart';

const categoryOrder = [
  'Gift Voucher & Packages',
  'Skirt',
  'Pant',
  'Dress',
  'Daraa',
  'Abayaa',
  'Jacket',
  'Coat',
  'Dishdasha',
  'Hijab/ Scarf',
  'Vest',
  'Short',
  'Jumpsuit',
  'Uniform',
  'Shirt',
  'Bisht',
  'Embroidery',
  'Curtain',
  'Other',
  'Gown',
  'Tailoring',
  'Ready itmes',
  'Delivery fee',
  'Jeans',
  'Backjob',
  'Partners/Disccount',
  'Special Offer',
];
const arabicCategories = {
  'Skirt': 'التنورة',
  'Pant': 'البنطلون',
  'Dress': 'الفستان',
  'Daraa': 'الدراعة',
  'Abayaa': 'العباية',
  'Jacket': 'الجاكيت',
  'Coat': 'المعطف',
  'Dishdasha': 'الدشداشة',
  'Shirt': 'القميص',
  'Bisht': 'البشت',
  'Vest': 'الصديري',
  'Uniform': 'الزي',
  'Short': 'الشورت',
  'Jumpsuit': 'الجمبسوت',
  'Gown': 'فستان السهرة',
  'Curtain': 'الستارة',
  'Hijab/ Scarf': 'الحجاب',
};
String arabicService(Json item) {
  final n = (item['name'] as String).toLowerCase();
  final c = arabicCategories[item['category']] ?? '';
  final String service;
  if (n.contains('additional') || n.contains('other service')) {
    service = 'خدمة إضافية';
  } else if (n.contains('size change')) {
    service = 'تعديل المقاس';
  } else if (n.contains('button with opening')) {
    service = 'زر مع فتحة';
  } else if (n.contains('blind hem')) {
    service = 'خياطة مخفية';
  } else if (n.contains('fusible')) {
    service = 'ثنية لاصقة';
  } else if (n.contains('waist')) {
    service = 'تعديل الخصر';
  } else if (n.contains('taper/lining')) {
    service = 'تضييق مع البطانة';
  } else if (n.contains('taper')) {
    service = 'تضييق';
  } else if (n.contains('add lining')) {
    service = 'إضافة بطانة';
  } else if (n.contains('lining')) {
    service = 'تقصير مع البطانة';
  } else if (n.contains('cuff')) {
    service = 'تعديل الحافة';
  } else if (n.contains('button')) {
    service = 'زر';
  } else if (n.contains('zipper')) {
    service = 'سحاب';
  } else if (n.contains('elastic')) {
    service = 'مطاط';
  } else if (n.contains('patch')) {
    service = 'ترقيع';
  } else if (n.contains('hook')) {
    service = 'خطاف';
  } else if (n.contains('slit')) {
    service = 'تعديل فتحة';
  } else if (n.contains('automatic')) {
    service = 'كبسة أوتوماتيك';
  } else if (n.contains('shoulder')) {
    service = 'رفع الكتف';
  } else if (n.contains('sleeve')) {
    service = 'تعديل الكم';
  } else if (n.contains('collar')) {
    service = 'ياقة';
  } else if (n.contains('hem') ||
      n.contains('length') ||
      n.contains('lenght')) {
    service = 'تقصير';
  } else {
    return c;
  }
  return '$service $c'.trim();
}

extension Cashier on AppState {
  Widget cashier() => LayoutBuilder(
    builder: (context, box) {
      final desktop = box.maxWidth >= 1050, tablet = box.maxWidth >= 720;
      return Column(
        children: [
          if (!desktop)
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => update(() => cartTab = 0),
                      icon: const Icon(Icons.grid_view, size: 17),
                      label: const Text('Items'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => update(() => cartTab = 1),
                      icon: Badge(
                        label: Text('${cart.length}'),
                        child: const Icon(
                          Icons.shopping_cart_outlined,
                          size: 17,
                        ),
                      ),
                      label: Text('Cart · ${money(total)} KWD'),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: desktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: box.maxWidth * .15, child: categories()),
                      Expanded(flex: 6, child: itemsArea(tablet: true)),
                      Expanded(flex: 4, child: cartArea()),
                    ],
                  )
                : cartTab == 1
                ? cartArea()
                : Row(
                    children: [
                      if (tablet) SizedBox(width: 180, child: categories()),
                      Expanded(child: itemsArea(tablet: tablet)),
                    ],
                  ),
          ),
        ],
      );
    },
  );
  Widget categories() => Container(
    margin: const EdgeInsets.fromLTRB(6, 5, 3, 5),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(5),
    ),
    child: ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            padding: const EdgeInsets.all(11),
            color: mint,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                value: invoiceKind,
                items: const [
                  DropdownMenuItem(value: 'sale', child: Text('Default')),
                  DropdownMenuItem(
                    value: 'quotation',
                    child: Text('Sales quotation'),
                  ),
                ],
                onChanged: (v) => update(() => invoiceKind = v!),
              ),
            ),
          ),
        ),
        ...categoryOrder
            .where((c) => catalogue.any((p) => p['category'] == c))
            .map(
              (c) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Material(
                  color: category == c ? mint : Colors.white,
                  borderRadius: BorderRadius.circular(5),
                  child: ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(vertical: -3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    selected: category == c,
                    selectedTileColor: mint,
                    title: Text(
                      c == 'Ready itmes' ? 'Ready items' : c,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                    onTap: () => update(() {
                      category = c;
                      search = '';
                    }),
                  ),
                ),
              ),
            ),
      ],
    ),
  );
  Widget itemsArea({required bool tablet}) {
    final filtered = catalogue
        .where(
          (p) =>
              p['active'] != 0 &&
              (search.isNotEmpty
                  ? ('${p['name']} ${p['id']} ${arabicService(p)}'
                        .toLowerCase()
                        .contains(search.toLowerCase()))
                  : p['category'] == category),
        )
        .toList();
    return Container(
      margin: const EdgeInsets.all(5),
      color: Colors.white,
      child: Column(
        children: [
          Container(
            height: 38,
            color: line,
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: selectCustomer,
                    icon: const Icon(Icons.person_outline, size: 16),
                    label: Text(
                      customer?['name'] ?? 'Walk-in customer',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => run(selectAggregator),
                    icon: const Icon(Icons.public, size: 16),
                    label: Text(
                      aggregator.isEmpty ? 'Aggregator' : aggregator,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Held orders',
                  onPressed: heldOrders,
                  icon: const Icon(Icons.pause_circle_outline, size: 19),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('$category-search'),
                    decoration: const InputDecoration(
                      hintText: 'Search item',
                      prefixIcon: Icon(Icons.search, size: 18),
                    ),
                    onChanged: (v) => update(() => search = v),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: tablet ? 180 : 125,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Scan barcode',
                      prefixIcon: Icon(Icons.qr_code_scanner, size: 17),
                    ),
                    onSubmitted: (value) {
                      final product = catalogue
                          .where(
                            (p) => p['id'] == value.trim() && p['active'] != 0,
                          )
                          .firstOrNull;
                      if (product != null) {
                        addItem(product);
                      } else {
                        notice('No item matches this barcode.', error: true);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          if (!tablet)
            SizedBox(
              height: 45,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: categoryOrder
                    .where((c) => catalogue.any((p) => p['category'] == c))
                    .map(
                      (c) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          label: Text(c == 'Ready itmes' ? 'Ready items' : c),
                          selected: category == c,
                          onSelected: (_) => update(() {
                            category = c;
                            search = '';
                          }),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? empty('No matching items')
                : LayoutBuilder(
                    builder: (context, box) {
                      final columns = box.maxWidth >= 550
                          ? 3
                          : box.maxWidth >= 340
                          ? 2
                          : 1;
                      return GridView.builder(
                        padding: const EdgeInsets.all(6),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          mainAxisExtent: 76,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final p = filtered[index];
                          return Material(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              side: const BorderSide(color: line),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: busy ? null : () => addItem(p),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Container(
                                          width: 42,
                                          color: const Color(0xffe0e0e5),
                                          child: const Icon(
                                            Icons.inventory_2_outlined,
                                            color: Color(0xffb7bdc9),
                                            size: 28,
                                          ),
                                        ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 4,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Text(
                                                  p['name'],
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  arabicService(p),
                                                  textDirection:
                                                      TextDirection.rtl,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 9,
                                                    color: muted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    height: 19,
                                    color: const Color(0xffe0e0e5),
                                    child: Center(
                                      child: Text(
                                        '${money(p['price'])} KWD',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> addItem(Json p) async {
    int price = p['price'];
    if (price == 0) {
      final result = await form('Set service price', [
        const Field(
          'price',
          'Price (KWD)',
          required: true,
          number: true,
          initial: '0.000',
        ),
      ]);
      if (result == null) return;
      try {
        price = parseMoney(result['price']);
      } catch (e) {
        notice(e, error: true);
        return;
      }
    }
    final i = cart.indexWhere(
      (l) =>
          l['id'] == p['id'] && l['price'] == price && (l['note'] ?? '') == '',
    );
    if (i >= 0 && cart[i]['qty'] >= 999) {
      notice('Maximum quantity is 999 per service line.', error: true);
      return;
    }
    update(() {
      if (i >= 0) {
        cart[i]['qty'] += 1;
        selected = i;
      } else {
        cart.add({...p, 'qty': 1, 'price': price, 'note': ''});
        selected = cart.length - 1;
      }
      keypad = '';
    });
  }

  Future<void> editService(int index) async {
    update(() {
      selected = index;
      keypad = '';
    });
    final item = cart[index];
    final product =
        catalogue.where((p) => p['id'] == item['id']).firstOrNull ?? item;
    final details = await serviceDetails(product, existing: item);
    if (details != null &&
        mounted &&
        index < cart.length &&
        identical(cart[index], item)) {
      update(() => cart[index] = {...item, ...details});
    }
  }

  Future<Json?> serviceDetails(Json product, {required Json existing}) async {
    final qty = TextEditingController(text: '${existing['qty']}');
    final price = TextEditingController(text: money(existing['price']));
    final instructions = TextEditingController(text: existing['note'] ?? '');
    final editablePrice = isManager || product['price'] == 0;
    final key = GlobalKey<FormState>();
    final result = await showDialog<Json>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.sizeOf(ctx).height - 60,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              modalHeader(product['name'], ctx),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Form(
                    key: key,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          arabicService(product),
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(color: muted),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: instructions,
                          minLines: 3,
                          maxLines: 5,
                          maxLength: 1000,
                          decoration: const InputDecoration(
                            labelText: 'Service notes / measurements',
                            hintText: 'Instructions for this garment only',
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: qty,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Quantity',
                                ),
                                validator: (v) {
                                  final n = int.tryParse(v ?? '');
                                  return n != null && n >= 1 && n <= 999
                                      ? null
                                      : 'Use 1?999';
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: price,
                                readOnly: !editablePrice,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: 'Price (KWD)',
                                  suffixIcon: !editablePrice
                                      ? const Icon(Icons.lock_outline, size: 17)
                                      : null,
                                ),
                                validator: (v) {
                                  try {
                                    parseMoney(v ?? '');
                                    return null;
                                  } catch (_) {
                                    return 'Use a valid KWD price';
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () {
                        if (key.currentState!.validate()) {
                          Navigator.pop(ctx, <String, dynamic>{
                            'qty': int.parse(qty.text),
                            'price': parseMoney(price.text),
                            'note': instructions.text.trim(),
                          });
                        }
                      },
                      child: const Text('Save service'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), () {
      qty.dispose();
      price.dispose();
      instructions.dispose();
    });
    return result;
  }

  Widget cartArea() => Container(
    margin: const EdgeInsets.fromLTRB(2, 5, 6, 5),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Column(
      children: [
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: line,
          child: const Row(
            children: [
              Expanded(
                child: Text(
                  'Item Name',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              SizedBox(
                width: 75,
                child: Text(
                  'QTY',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  'Price',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11),
                ),
              ),
              SizedBox(
                width: 65,
                child: Text(
                  'Amount',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: cart.isEmpty
              ? empty('Cart is empty', icon: Icons.shopping_bag_outlined)
              : ListView.builder(
                  itemCount: cart.length,
                  itemBuilder: (context, index) {
                    final l = cart[index];
                    return Material(
                      color: selected == index
                          ? const Color(0xffeff8f2)
                          : Colors.white,
                      child: InkWell(
                        onTap: () => editService(index),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: line)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => editService(index),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l['name'],
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (arabic)
                                        Text(
                                          arabicService(l),
                                          textDirection: TextDirection.rtl,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: muted,
                                          ),
                                        ),
                                      Text(
                                        l['note'].toString().isEmpty
                                            ? '${l['id']}'
                                            : l['note'],
                                        maxLines: 2,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 75,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    tiny(
                                      Icons.remove,
                                      () => changeQty(index, -1),
                                    ),
                                    Text(
                                      '${l['qty']}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                    tiny(Icons.add, () => changeQty(index, 1)),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 64,
                                child: InkWell(
                                  onTap: () => editPrice(index),
                                  child: Text(
                                    money(l['price']),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 65,
                                child: Text(
                                  money(l['qty'] * l['price']),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              if (selected == index)
                                SizedBox(
                                  width: 22,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    iconSize: 15,
                                    onPressed: () => update(() {
                                      cart.removeAt(index);
                                      selected = -1;
                                    }),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: line)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              totalLabel('Disc.', actualDiscount, onTap: manualDiscount),
              totalLabel('Extra', extra, onTap: addExtra),
              totalLabel('Sub', subtotal),
              totalLabel('Tax 0%', 0),
              totalLabel('TOTAL', total, large: true),
            ],
          ),
        ),
        if (restored != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Resuming ${restored!['bill']}',
              style: const TextStyle(color: muted, fontSize: 10),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(4),
          child: LayoutBuilder(
            builder: (context, box) {
              final height = MediaQuery.sizeOf(context).height < 670
                  ? 38.0
                  : 46.0;
              return Column(
                children: [
                  for (var row = 0; row < 4; row++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: height,
                              child: keyAction(row),
                            ),
                          ),
                          for (var col = 0; col < 3; col++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: SizedBox(
                                  height: height,
                                  child: keyNumber(row, col),
                                ),
                              ),
                            ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: SizedBox(
                                height: height,
                                child: sideAction(row),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
  Widget tiny(IconData icon, VoidCallback fn) => SizedBox(
    width: 21,
    height: 24,
    child: IconButton(
      padding: EdgeInsets.zero,
      onPressed: busy ? null : fn,
      icon: Icon(icon, size: 14, color: green),
    ),
  );
  Widget totalLabel(
    String label,
    int value, {
    bool large = false,
    VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: mint,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          money(value),
          style: TextStyle(
            fontSize: large ? 19 : 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
  Widget tileButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback? action, {
    Color textColor = Colors.white,
  }) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: textColor,
      padding: const EdgeInsets.all(2),
    ),
    onPressed: busy ? null : action,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 9),
        ),
      ],
    ),
  );
  Widget keyAction(int row) => switch (row) {
    0 => tileButton('Document', Icons.attach_file, mint, uploadDocument),
    1 => tileButton('Salesman', Icons.person_outline, ink, selectStaff),
    2 => tileButton('Coupons', Icons.discount_outlined, mint, selectCoupon),
    _ => tileButton('Order Notes', Icons.note_alt_outlined, ink, orderNotes),
  };
  Widget keyNumber(int row, int col) {
    if (row == 3 && col == 2) {
      return tileButton(
        'Save Unpaid',
        Icons.receipt_long,
        const Color(0xff888894),
        () => saveOrder(invoiceKind),
      );
    }
    final label = row == 3 ? (col == 0 ? '.' : '0') : '${row * 3 + col + 1}';
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white,
      ),
      onPressed: busy
          ? null
          : () {
              if (label == '.') {
                if (selected >= 0) editPrice(selected);
                return;
              }
              if (selected < 0) {
                notice('Select a cart line first.');
                return;
              }
              final input = keypad + label;
              final qty = int.tryParse(input) ?? 0;
              if (qty > 999) return;
              update(() {
                keypad = input;
                if (qty > 0) cart[selected]['qty'] = qty;
              });
            },
      child: Text(
        label,
        style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget sideAction(int row) => switch (row) {
    0 => tileButton('Clear All', Icons.clear_all, Colors.redAccent, () async {
      if (cart.isEmpty ||
          await confirm(
            'Clear cart?',
            'Remove all items from the current order?',
          )) {
        update(clearCart);
      }
    }),
    1 => tileButton('Disc.', Icons.percent, mint, manualDiscount),
    2 => tileButton(
      'Hold',
      Icons.tag,
      const Color(0xffffa132),
      () => saveOrder('held'),
    ),
    _ => tileButton(
      invoiceKind == 'quotation' ? 'Save quotation' : 'Pay & Print',
      Icons.print_outlined,
      green,
      invoiceKind == 'quotation' ? () => saveOrder('quotation') : checkout,
    ),
  };
  void changeQty(int i, int amount) {
    final qty = cart[i]['qty'] + amount;
    if (qty < 1 || qty > 999) return;
    update(() {
      cart[i]['qty'] = qty;
      selected = i;
      keypad = '';
    });
  }

  Future<void> editPrice(int i) async {
    final item = cart[i];
    final original = catalogue.firstWhere((p) => p['id'] == item['id']);
    if (!isManager && original['price'] != 0) {
      notice('Only a manager can change fixed prices.', error: true);
      return;
    }
    final result = await form('Item price', [
      Field(
        'price',
        'Price (KWD)',
        initial: money(item['price']),
        number: true,
        required: true,
      ),
    ]);
    if (result != null) {
      try {
        final price = parseMoney(result['price']);
        update(() => cart[i]['price'] = price);
      } catch (e) {
        notice(e, error: true);
      }
    }
  }

  Future<void> orderNotes() async {
    final result = await form('Order Notes', [
      Field('notes', 'Order notes', initial: notes, multiline: true),
      Field('due', 'Collection date (YYYY-MM-DD)', initial: dueDate),
    ]);
    if (result != null) {
      final due = result['due'] as String;
      if (due.isNotEmpty && DateTime.tryParse(due) == null) {
        notice('Enter a valid collection date.', error: true);
        return;
      }
      update(() {
        notes = result['notes'];
        dueDate = due;
      });
    }
  }

  Future<void> selectAggregator() async {
    final result = await form('Aggregator', [
      Field('name', 'Partner / aggregator', initial: aggregator),
    ]);
    if (result != null) update(() => aggregator = result['name']);
  }

  Future<void> manualDiscount() async {
    if (!isManager) {
      notice('Use Coupons, or ask a manager for a manual discount.');
      return;
    }
    final result = await form('Discount', [
      Field(
        'amount',
        'Discount (KWD)',
        initial: money(actualDiscount),
        number: true,
        required: true,
      ),
    ]);
    if (result != null) {
      try {
        final value = parseMoney(result['amount']);
        if (value > subtotal) throw Exception('Discount exceeds subtotal.');
        update(() {
          discount = value;
          coupon = null;
        });
      } catch (e) {
        notice(e, error: true);
      }
    }
  }

  Future<void> addExtra() async {
    if (!isManager) {
      notice('A manager can add extra charges.');
      return;
    }
    final result = await form('Extra charge', [
      Field(
        'amount',
        'Amount (KWD)',
        initial: money(extra),
        number: true,
        required: true,
      ),
    ]);
    if (result != null) {
      try {
        final value = parseMoney(result['amount']);
        update(() => extra = value);
      } catch (e) {
        notice(e, error: true);
      }
    }
  }

  Future<void> selectStaff() async {
    await modal(
      'Salesman',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (employees.isEmpty) const Text('No employees are available.'),
          ...employees.map(
            (s) => ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(s['name']),
              subtitle: Text(s['role']),
              trailing: staff == s['id']
                  ? const Icon(Icons.check, color: green)
                  : null,
              onTap: () {
                update(() => staff = s['id']);
                Navigator.pop(context);
              },
            ),
          ),
          ListTile(
            title: const Text('Unassigned'),
            onTap: () {
              update(() => staff = '');
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> selectCoupon() async {
    await modal(
      'Coupons & Vouchers',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...AppState.maps(boot?['coupons']).map(
            (c) => ListTile(
              title: Text(c['name']),
              subtitle: Text('Minimum 0 · ${c['percent']}% off'),
              trailing: FilledButton(
                onPressed: () {
                  update(() {
                    coupon = c['id'];
                    discount = 0;
                  });
                  Navigator.pop(context);
                },
                child: const Text('Apply'),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              update(() {
                coupon = null;
                discount = 0;
              });
              Navigator.pop(context);
            },
            child: const Text('Remove coupon'),
          ),
        ],
      ),
    );
  }

  Future<void> uploadDocument() async {
    await run(() async {
      if (docs.length >= 10) throw Exception('Maximum 10 documents per order.');
      final file = await browser.pickFile();
      if (file == null) return;
      if (file.bytes.length > 5 * 1024 * 1024) {
        throw Exception('Maximum file size is 5 MB.');
      }
      final saved = await Api.upload(
        branch!['id'],
        file.bytes,
        file.type,
        file.name,
      );
      update(() => docs.add(saved));
      notice('Document attached: ${saved['name']}');
    });
  }

  Future<void> heldOrders() async {
    final saved = orders.where((o) => o['kind'] == 'held').toList();
    await modal(
      'Held orders',
      saved.isEmpty
          ? empty('No held orders')
          : Column(
              children: saved
                  .map(
                    (o) => ListTile(
                      title: Text(o['bill']),
                      subtitle: Text(
                        '${o['customer_name']} · ${money(o['total'])} KWD',
                      ),
                      trailing: const Icon(Icons.play_arrow_outlined),
                      onTap: () async {
                        Navigator.pop(context);
                        await restore(o);
                      },
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Future<void> restore(Json o) async {
    if (cart.isNotEmpty &&
        !await confirm(
          'Replace current cart?',
          'Load this saved order into the POS?',
        )) {
      return;
    }
    final detail = Json.from(await Api.get('orders/${o['id']}'));
    o = Json.from(detail['order']);
    update(() {
      clearCart();
      restored = o;
      draftTailorId = o['tailor_id'] ?? '';
      docs = AppState.maps(detail['attachments']);
      coupon = o['coupon']?.toString().isNotEmpty == true ? o['coupon'] : null;
      invoiceKind = 'sale';
      cart = AppState.maps(o['lines']);
      customer = o['customer_id'] != null
          ? {
              'id': o['customer_id'],
              'name': o['customer_name'],
              'phone': o['phone'],
              'address': o['address'],
            }
          : null;
      discount = o['discount'];
      extra = o['extra'];
      notes = o['notes'];
      staff = o['staff'];
      aggregator = o['aggregator'];
      dueDate = o['due_date'];
      screen = 2;
      cartTab = 0;
    });
  }

  Future<void> checkout() async {
    if (cart.isEmpty) {
      notice('Add an item first.');
      return;
    }
    final rows = <Json>[];
    String method = methods.first, amount = money(total), reference = '';
    final result = await showDialog<List<Json>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final paid = rows.fold<int>(0, (s, r) => s + r['amount'] as int);
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 530, maxHeight: 650),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  modalHeader('Payment', ctx),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          moneyText(total, size: 30),
                          const SizedBox(height: 6),
                          Text(
                            'Balance: ${money(total - paid)} KWD',
                            style: const TextStyle(color: muted),
                          ),
                          const SizedBox(height: 20),
                          TextButton.icon(
                            onPressed: () async {
                              final id = await chooseTailor(
                                branch!['id'],
                                draftTailorId,
                              );
                              if (id != null) set(() => draftTailorId = id);
                            },
                            icon: const Icon(Icons.content_cut, size: 17),
                            label: Text(
                              'Tailor: ${tailorLabel(draftTailorId)}',
                            ),
                          ),
                          DropdownButtonFormField<String>(
                            initialValue: method,
                            decoration: const InputDecoration(
                              labelText: 'Payment method',
                            ),
                            items: methods
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => set(() => method = v!),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: ValueKey('payment-$paid'),
                            initialValue: amount,
                            decoration: const InputDecoration(
                              labelText: 'Amount received (KWD)',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (v) => amount = v,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            decoration: const InputDecoration(
                              labelText:
                                  'Reference / terminal receipt (optional)',
                            ),
                            onChanged: (v) => reference = v,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Confirm Cash, K-NET or card payment was received before recording it.',
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              try {
                                final value = parseMoney(amount);
                                if (value <= 0 || value > total - paid) {
                                  throw Exception(
                                    'Enter an amount up to the remaining balance.',
                                  );
                                }
                                set(() {
                                  rows.add({
                                    'amount': value,
                                    'method': method,
                                    'reference': reference,
                                  });
                                  amount = money(total - paid - value);
                                });
                              } catch (e) {
                                notice(e, error: true);
                              }
                            },
                            icon: const Icon(Icons.add, size: 17),
                            label: const Text('Add payment / split payment'),
                          ),
                          ...rows.asMap().entries.map(
                            (entry) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${entry.value['method']} · ${money(entry.value['amount'])} KWD',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 17),
                                onPressed: () => set(() {
                                  rows.removeAt(entry.key);
                                  amount = money(
                                    total -
                                        rows.fold<int>(
                                          0,
                                          (s, r) => s + (r['amount'] as int),
                                        ),
                                  );
                                }),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () {
                            try {
                              final result = rows
                                  .map((r) => Json.from(r))
                                  .toList();
                              if (amount.isNotEmpty && parseMoney(amount) > 0) {
                                final value = parseMoney(amount);
                                if (value > total - paid) {
                                  throw Exception('Payment exceeds balance.');
                                }
                                result.add({
                                  'amount': value,
                                  'method': method,
                                  'reference': reference,
                                });
                              }
                              Navigator.pop(ctx, result);
                            } catch (e) {
                              notice(e, error: true);
                            }
                          },
                          child: const Text('Record & print'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result != null) {
      await saveOrder('sale', paymentRows: result, printReceipt: true);
    }
  }

  Future<void> saveOrder(
    String kind, {
    List<Json> paymentRows = const [],
    bool printReceipt = false,
  }) async {
    if (cart.isEmpty) {
      notice('Add an item first.');
      return;
    }
    Json? savedInvoice;
    await run(() async {
      final data = <String, dynamic>{
        'id': draftId,
        'tailorId': draftTailorId,
        'branch': branch!['id'],
        'kind': kind,
        'lines': cart,
        'customerId': customer?['id'],
        'coupon': coupon,
        'discount': discount,
        'extra': extra,
        'notes': notes,
        'staff': staff,
        'aggregator': aggregator,
        'dueDate': dueDate,
        'attachments': docs.map((d) => d['id']).toList(),
        'payments': paymentRows,
        if (restored != null) 'sourceId': restored!['id'],
        if (restored != null) 'sourceVersion': restored!['version'],
      };
      final order = Json.from(await Api.post('orders', data));
      savedInvoice = order;
      update(clearCart);
      await loadData();
      notice(
        kind == 'held'
            ? 'Order held.'
            : kind == 'quotation'
            ? 'Quotation saved.'
            : 'Sale saved: ${order['bill']}',
      );
    });
    if (printReceipt && savedInvoice != null) await receipt(savedInvoice!);
  }
}
