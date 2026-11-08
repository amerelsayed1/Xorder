import 'dart:convert';
import 'dart:io';

import 'package:xorder_pos_cloud/data/cloud/bootstrap_bundle.dart';

/// One-off integration probe: parse a real `/api/pos/bootstrap` response with
/// the exact code the till runs, and report what survived.
void main(List<String> args) {
  final json = jsonDecode(File(args.first).readAsStringSync());
  final bundle = BootstrapBundle.tryParse(json);
  if (bundle == null) {
    stderr.writeln('UNPARSEABLE');
    exit(1);
  }
  stdout.writeln('config_version: ${bundle.configVersion}');
  stdout.writeln('seedable: ${bundle.seedable}');
  stdout.writeln('business: ${bundle.business?.slug} '
      '${bundle.business?.currency}/${bundle.business?.exponent}');
  stdout.writeln('terminal: ${bundle.terminal?.id} branch ${bundle.terminal?.branchId}');
  stdout.writeln('branches: ${bundle.branches.length} '
      '(first code: ${bundle.branches.isEmpty ? '-' : bundle.branches.first.code})');
  stdout.writeln('categories: ${bundle.categories.length}');
  stdout.writeln('products: ${bundle.products.length} '
      '(first: ${bundle.products.isEmpty ? '-' : '${bundle.products.first.nameEn} @ ${bundle.products.first.priceMinor}'})');
  stdout.writeln('optionGroups: ${bundle.optionGroups.length}');
  stdout.writeln('tables: ${bundle.tables.length}');
  stdout.writeln('staff: ${bundle.staff.length} '
      '(first pin: ${bundle.staff.isEmpty ? '-' : bundle.staff.first.pin?.iterations})');
  stdout.writeln('tenderTypes: ${(bundle.money['tender_types'] as List?)?.length}');
  final dropped = (jsonDecode(File(args.first).readAsStringSync())
          as Map)['catalog']['items']['data'].length - bundle.products.length;
  stdout.writeln('products dropped by parser: $dropped');
}
