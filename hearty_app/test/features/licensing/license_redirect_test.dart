import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/features/licensing/license_provider.dart';

void main() {
  group('licenseRedirect', () {
    test('unauthenticated → no licensing redirect (auth gate handles it)', () {
      expect(
        licenseRedirect(
          isAuthenticated: false,
          status: 'none',
          location: '/home',
        ),
        isNull,
      );
    });

    test('active license → no redirect from a normal screen', () {
      expect(
        licenseRedirect(
          isAuthenticated: true,
          status: 'active',
          location: '/home',
        ),
        isNull,
      );
    });

    test('non-active license → routes to /no-access', () {
      expect(
        licenseRedirect(
          isAuthenticated: true,
          status: 'none',
          location: '/home',
        ),
        '/no-access',
      );
      expect(
        licenseRedirect(
          isAuthenticated: true,
          status: 'revoked',
          location: '/home',
        ),
        '/no-access',
      );
    });

    test('null status (loading/error) → fail-open, no redirect', () {
      expect(
        licenseRedirect(
          isAuthenticated: true,
          status: null,
          location: '/home',
        ),
        isNull,
      );
    });

    test('already on /no-access with non-active status → no further redirect',
        () {
      expect(
        licenseRedirect(
          isAuthenticated: true,
          status: 'revoked',
          location: '/no-access',
        ),
        isNull,
      );
    });

    test('on /no-access but license now active → back to /home', () {
      expect(
        licenseRedirect(
          isAuthenticated: true,
          status: 'active',
          location: '/no-access',
        ),
        '/home',
      );
    });

    test('on /no-access while status still loading → stay (no redirect)', () {
      expect(
        licenseRedirect(
          isAuthenticated: true,
          status: null,
          location: '/no-access',
        ),
        isNull,
      );
    });
  });

  group('inLicensedArea', () {
    test('false when unauthenticated', () {
      expect(inLicensedArea(isAuthenticated: false, location: '/home'), isFalse);
    });
    test('false on auth/setup screens', () {
      for (final loc in ['/sign-in', '/setup', '/notification-setup', '/conversation-style-setup']) {
        expect(inLicensedArea(isAuthenticated: true, location: loc), isFalse, reason: loc);
      }
    });
    test('true on onboarding (so gated users are diverted before onboarding)', () {
      expect(inLicensedArea(isAuthenticated: true, location: '/onboarding'), isTrue);
    });
    test('true in the app proper', () {
      expect(inLicensedArea(isAuthenticated: true, location: '/home'), isTrue);
    });
  });
}
