import 'package:chatwoot_sdk/data/local/entity/chatwoot_contact.dart';
import 'package:chatwoot_sdk/data/local/entity/chatwoot_conversation.dart';
import 'package:chatwoot_sdk/data/local/local_storage.dart';
import 'package:chatwoot_sdk/data/remote/service/chatwoot_client_auth_service.dart';
import 'package:dio/dio.dart';
import 'package:synchronized/synchronized.dart' as synchronized;

///Intercepts network requests and attaches inbox identifier, contact identifiers, conversation identifiers
class ChatwootClientApiInterceptor extends Interceptor {
  static const INTERCEPTOR_INBOX_IDENTIFIER_PLACEHOLDER = "{INBOX_IDENTIFIER}";
  static const INTERCEPTOR_CONTACT_IDENTIFIER_PLACEHOLDER =
      "{CONTACT_IDENTIFIER}";
  static const INTERCEPTOR_CONVERSATION_IDENTIFIER_PLACEHOLDER =
      "{CONVERSATION_IDENTIFIER}";

  final String _inboxIdentifier;
  final LocalStorage _localStorage;
  final ChatwootClientAuthService _authService;
  final requestLock = synchronized.Lock();
  final responseLock = synchronized.Lock();

  ChatwootClientApiInterceptor(
      this._inboxIdentifier, this._localStorage, this._authService);

  /// Creates a new contact and conversation when no persisted contact is found when an api call is made
  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    await requestLock.synchronized(() async {
      try {
        RequestOptions newOptions = options;
        ChatwootContact? contact = _localStorage.contactDao.getContact();
        ChatwootConversation? conversation =
            _localStorage.conversationDao.getConversation();

        if (contact == null) {
          // create new contact from user if no token found
          contact = await _authService.createNewContact(
              _inboxIdentifier, _localStorage.userDao.getUser());
          conversation = await _authService.createNewConversation(
              _inboxIdentifier, contact.contactIdentifier ?? "");
          await _localStorage.conversationDao.saveConversation(conversation);
          await _localStorage.contactDao.saveContact(contact);
        }

        if (conversation == null) {
          conversation = await _authService.createNewConversation(
              _inboxIdentifier, contact.contactIdentifier ?? "");
          await _localStorage.conversationDao.saveConversation(conversation);
        }

        if (newOptions.data is Map &&
            _localStorage.userDao.getUser()?.customAttributes != null) {
          final userAttributes =
              _localStorage.userDao.getUser()!.customAttributes;
          if (userAttributes is Map) {
            if (newOptions.data['custom_attributes'] == null) {
              newOptions.data['custom_attributes'] = userAttributes;
            } else {
              (newOptions.data['custom_attributes'] as Map)
                  .addAll(userAttributes);
            }
          }
        }

        newOptions.path = newOptions.path.replaceAll(
            INTERCEPTOR_INBOX_IDENTIFIER_PLACEHOLDER, _inboxIdentifier);
        newOptions.path = newOptions.path.replaceAll(
            INTERCEPTOR_CONTACT_IDENTIFIER_PLACEHOLDER,
            contact.contactIdentifier ?? "");
        newOptions.path = newOptions.path.replaceAll(
            INTERCEPTOR_CONVERSATION_IDENTIFIER_PLACEHOLDER,
            "${conversation.id}");

        handler.next(newOptions);
      } catch (e) {
        handler.reject(DioException(requestOptions: options, error: e));
      }
    });
  }

  /// Clears and recreates contact when a 401 (Unauthorized), 403 (Forbidden) or 404 (Not found)
  /// response is returned from chatwoot public client api
  @override
  Future<void> onResponse(
      Response response, ResponseInterceptorHandler handler) async {
    await responseLock.synchronized(() async {
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 404) {
        print(
            "Chatwoot: Unauthorized or Deleted (${response.statusCode}). Re-authenticating...");

        // Clear everything locally
        await _localStorage.clear(clearChatwootUserStorage: false);

        try {
          // 1. Create new contact
          final contact = await _authService.createNewContact(
              _inboxIdentifier, _localStorage.userDao.getUser());
          await _localStorage.contactDao.saveContact(contact);

          // 2. Create new conversation
          final conversation = await _authService.createNewConversation(
              _inboxIdentifier, contact.contactIdentifier ?? "");
          await _localStorage.conversationDao.saveConversation(conversation);

          // 3. Prepare the original request to be retried
          RequestOptions newOptions = response.requestOptions;
          newOptions.path = newOptions.path.replaceAll(
              INTERCEPTOR_INBOX_IDENTIFIER_PLACEHOLDER, _inboxIdentifier);
          newOptions.path = newOptions.path.replaceAll(
              INTERCEPTOR_CONTACT_IDENTIFIER_PLACEHOLDER,
              contact.contactIdentifier ?? "");
          newOptions.path = newOptions.path.replaceAll(
              INTERCEPTOR_CONVERSATION_IDENTIFIER_PLACEHOLDER,
              "${conversation.id}");

          // Retry the request using AuthService's clean dio
          final retryResponse = await _authService.dio.fetch(newOptions);
          handler.resolve(retryResponse);
        } catch (e) {
          print("Chatwoot: Re-authentication failed: $e");
          handler.next(response); // If re-auth fails, return original error
        }
      } else {
        handler.next(response);
      }
    });
  }
}

extension Range on num {
  bool isBetween(num from, num to) {
    return from < this && this < to;
  }
}
