import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/services/messaging_service.dart';

/// Přijímací cesta zahazuje obsah neznámého typu (ACK + drop, protože po
/// upgradu už nejde dešifrovat znovu). Každý typ, který appka sama posílá,
/// proto MUSÍ být v množině známých typů. V 1.2.0 tu chyběl `call` — každá
/// nabídka hovoru se tiše zahodila a hovory nešly přijmout.
void main() {
  test('všechny odesílané typy obsahu umí přijímací cesta zpracovat', () {
    const sent = {
      'txt', 'att', 'rx', 'edit', 'del', 'dlv', 'rr', 'typ', 'vote', 'call',
      'ginv', 'gleave', 'gmeta', 'gop', 'gsync',
    };
    expect(MessagingService.knownContentTypes, containsAll(sent));
  });

  test('signalizace hovoru je známý typ', () {
    expect(MessagingService.knownContentTypes, contains('call'));
  });
}
