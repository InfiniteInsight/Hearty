import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Emits the current [User?] immediately on subscription, then re-emits on
/// every auth state change. Using async* ensures cold-start behaviour is
/// correct even if [onAuthStateChange] doesn't replay the current session.
final authStateProvider = StreamProvider<User?>((ref) async* {
  yield Supabase.instance.client.auth.currentUser;
  yield* Supabase.instance.client.auth.onAuthStateChange
      .map((event) => event.session?.user);
});

/// Synchronous convenience provider derived from [authStateProvider].
/// Returns null while the stream hasn't emitted yet (loading) or when
/// the user is signed out.
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});
