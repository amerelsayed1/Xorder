import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/features/licensing/data/licence_service.dart';

/// The `Fake…` repositories, bound explicitly.
///
/// These stopped being the app's default bindings when the till moved onto the
/// branch database. They had to: nothing distinguished a release build, so
/// every installation — including a real restaurant's — opened showing a
/// fictional menu, a fictional floor plan and a cashier who does not work
/// there, while the money path wrote real rows to a real database.
///
/// They remain exactly what a widget test wants: fast, deterministic, and
/// needing no server. So a test asks for them by name, which also means the
/// test says out loud that its data is invented — the thing the old default
/// binding never did.
///
/// A test that wants a real database wants `test/data/pg_fixture.dart` instead.
List<Override> fakeRepositoryOverrides() => [
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      tablesRepositoryProvider.overrideWithValue(FakeTablesRepository()),
      sessionRepositoryProvider.overrideWithValue(FakeSessionRepository()),
      branchRepositoryProvider.overrideWithValue(FakeBranchRepository()),
      provisioningRepositoryProvider.overrideWithValue(FakeProvisioningRepository()),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      shiftRepositoryProvider.overrideWithValue(FakeShiftRepository()),
      hardwarePortsProvider.overrideWithValue(FakeHardwarePorts()),
      // The development issuer, which self-signs. The app binds
      // `DefaultLicenceService` against the real embedded key, so a widget
      // test that wanted a working licence would otherwise have to sign one.
      licenceServiceProvider.overrideWithValue(FakeLicenceService()),
    ];
