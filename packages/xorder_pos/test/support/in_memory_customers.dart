import 'package:xorder_pos/domain/models/customer.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/domain/services/authorization.dart';

/// A customer directory in memory, for widget tests.
///
/// It refuses what the Postgres repository refuses — an [upsert] by somebody
/// without `customers.create` throws [CustomerNotPermitted] — and it records
/// who asked, so a test can say the check used the person at the till.
class InMemoryCustomers implements CustomersRepository {
  InMemoryCustomers([Iterable<PosCustomer> seed = const []])
    : customers = [...seed];

  final List<PosCustomer> customers;

  /// Who each [upsert] was made by, in order.
  final List<PosStaff?> upsertedBy = [];

  @override
  Future<List<PosCustomer>> search(String query, {int limit = 30}) async {
    if (query.trim().isEmpty) return customers.take(limit).toList();
    return customers.where((c) => c.matches(query)).take(limit).toList();
  }

  @override
  Future<PosCustomer> upsert({
    required PosStaff? by,
    required String name,
    required String phone,
    String? email,
    String? address,
    String? note,
  }) async {
    if (Authorization.check(by, PosCapability.customersCreate) is! Allowed) {
      throw const CustomerNotPermitted();
    }
    upsertedBy.add(by);
    final created = PosCustomer(
      id: customers.length + 1,
      name: name.trim(),
      phone: PosCustomer.normalisePhone(phone),
      address: address,
    );
    customers.add(created);
    return created;
  }
}
