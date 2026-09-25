import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/kyc_document_upload_screen.dart';
import 'package:frontend/widgets/primary_button.dart';
import 'package:frontend/widgets/secondary_button.dart';

class MockAuthProvider extends AuthProvider {
  UserProfile? _mockUser;
  bool uploadDocumentCalled = false;
  String? lastDocType;
  List<int>? lastFileBytes;
  String? lastFilename;
  bool mockUploadSuccess = true;

  MockAuthProvider(
    super.apiClient, {
    UserProfile? initialUser,
  }) : _mockUser = initialUser;

  @override
  UserProfile? get user => _mockUser;

  void setMockUser(UserProfile user) {
    _mockUser = user;
    notifyListeners();
  }

  @override
  Future<void> fetchUserProfile() async {
    // No-op or update mock user state
  }

  @override
  Future<bool> uploadDocument({
    required String docType,
    required List<int> fileBytes,
    required String filename,
  }) async {
    uploadDocumentCalled = true;
    lastDocType = docType;
    lastFileBytes = fileBytes;
    lastFilename = filename;

    if (mockUploadSuccess && _mockUser != null) {
      // Simulate updating document path on user
      String? newIdFront = _mockUser!.idFrontDoc;
      String? newIdBack = _mockUser!.idBackDoc;
      String? newSelfie = _mockUser!.selfieDoc;
      String? newBusiness = _mockUser!.businessProofDoc;

      if (docType == 'id_front') {
        newIdFront = 'kyb/user-1/id_front.jpg';
      }
      if (docType == 'id_back') {
        newIdBack = 'kyb/user-1/id_back.jpg';
      }
      if (docType == 'selfie') {
        newSelfie = 'kyb/user-1/selfie.jpg';
      }
      if (docType == 'business_proof') {
        newBusiness = 'kyb/user-1/business_proof.pdf';
      }

      _mockUser = UserProfile(
        id: _mockUser!.id,
        email: _mockUser!.email,
        username: _mockUser!.username,
        role: _mockUser!.role,
        kycStatus: _mockUser!.role == 'owner'
            ? 'pending_super_admin_approval'
            : _mockUser!.kycStatus,
        kyeStatus: _mockUser!.role == 'employee'
            ? 'pending_super_admin_approval'
            : _mockUser!.kyeStatus,
        rejectionReason: _mockUser!.rejectionReason,
        idFrontDoc: newIdFront,
        idBackDoc: newIdBack,
        selfieDoc: newSelfie,
        businessProofDoc: newBusiness,
      );
      notifyListeners();
      return true;
    }
    return false;
  }
}

/// ApiClient stub for the A4 test: login succeeds (arming token + user),
/// while GET /auth/user fails until [failProfileFetch] is flipped.
class _KycRefreshMockApiClient extends ApiClient {
  int profileGetCalls = 0;
  bool failProfileFetch = true;

  _KycRefreshMockApiClient() : super(baseUrl: 'http://localhost:3002');

  Map<String, dynamic> _userMap() => {
        'user_id': 'employee-101',
        'email': 'employee@test.com',
        'username': 'testemployee',
        'role': 'employee',
        'kyc_status': '',
      };

  @override
  Future<dynamic> post(String path, Map<String, dynamic> body,
      {bool isRetry = false,
      Map<String, String>? queryParams,
      Map<String, String>? headers}) async {
    if (path == '/auth/login') {
      return {
        'token': 'test-token',
        ..._userMap(),
      };
    }
    return {'status': 'ok'};
  }

  @override
  Future<dynamic> get(String path,
      {Map<String, String>? queryParams,
      Map<String, String>? headers,
      bool isRetry = false}) async {
    if (path == '/auth/user') {
      profileGetCalls++;
      if (failProfileFetch) {
        throw ApiClientException('profile fetch failed', statusCode: 500);
      }
      return _userMap();
    }
    return {'status': 'ok'};
  }
}

/// MockAuthProvider variant for the A10 test: fetchUserProfile can be held
/// open behind [refreshGate] so the busy state is observable.
class _GatedRefreshMockAuthProvider extends MockAuthProvider {
  Completer<void>? refreshGate;
  int refreshCalls = 0;

  _GatedRefreshMockAuthProvider(
    super.apiClient, {
    super.initialUser,
  });

  @override
  Future<void> fetchUserProfile() async {
    refreshCalls++;
    final gate = refreshGate;
    if (gate != null) {
      await gate.future;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  setUp(() {
    // Each test starts with empty secure storage so AuthProvider
    // auto-login can never fire from a previous test's login writes and
    // trigger an extra fetchUserProfile (which would pollute refresh-call
    // counts in the A4/A10 tests below).
    FlutterSecureStorage.setMockInitialValues({});
  });

  final ownerUser = UserProfile(
    id: 'owner-101',
    email: 'owner@test.com',
    username: 'testowner',
    role: 'owner',
    kycStatus: '',
  );

  final employeeUser = UserProfile(
    id: 'employee-101',
    email: 'employee@test.com',
    username: 'testemployee',
    role: 'employee',
    kyeStatus: '',
  );

  testWidgets(
      '(a) Empty state shows all required upload slots for the role (4 for owner, 3 for employee)',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockAuth = MockAuthProvider(apiClient, initialUser: ownerUser);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: const KycDocumentUploadScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Owner role displays 4 slots
    expect(find.text('Owner Verification (KYB)'), findsOneWidget);
    expect(find.text('ID Card (Front)'), findsOneWidget);
    expect(find.text('ID Card (Back)'), findsOneWidget);
    expect(find.text('Selfie Photo'), findsOneWidget);
    expect(find.text('Business Proof / Commercial Register'), findsOneWidget);
    expect(find.text('Upload Document'), findsNWidgets(4));

    // Switch to Employee role and verify 3 slots
    mockAuth.setMockUser(employeeUser);
    await tester.pumpAndSettle();

    expect(find.text('Employee Verification (KYE)'), findsOneWidget);
    expect(find.text('ID Card (Front)'), findsOneWidget);
    expect(find.text('ID Card (Back)'), findsOneWidget);
    expect(find.text('Selfie Photo'), findsOneWidget);
    expect(find.text('Business Proof / Commercial Register'), findsNothing);
    expect(find.text('Upload Document'), findsNWidgets(3));
  });

  testWidgets('(b) Successful upload shows the uploaded state',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockAuth = MockAuthProvider(apiClient, initialUser: ownerUser);

    final kTransparentPng = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);

    Future<PickedDocumentFile?> mockPicker(
        BuildContext context, String slotKey, bool allowPdf) async {
      return PickedDocumentFile(
        filename: 'id_front_sample.png',
        bytes: kTransparentPng,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: KycDocumentUploadScreen(onPickFile: mockPicker),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Upload Document for ID Card (Front) - the first button
    await tester.tap(find.text('Upload Document').first);
    await tester.pumpAndSettle();

    // Verify upload document was called and slot transitioned to Uploaded state
    expect(mockAuth.uploadDocumentCalled, isTrue);
    expect(mockAuth.lastDocType, 'id_front');
    expect(mockAuth.lastFilename, 'id_front_sample.png');
    expect(find.text('UPLOADED'), findsWidgets);
    expect(find.text('Replace Document'), findsWidgets);
  });

  testWidgets(
      '(c) Oversized / wrong-format file is rejected client-side with a clear message before any network call',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockAuth = MockAuthProvider(apiClient, initialUser: ownerUser);

    // 1. Test Oversized File (>10MB)
    Future<PickedDocumentFile?> oversizedPicker(
        BuildContext context, String slotKey, bool allowPdf) async {
      return PickedDocumentFile(
        filename: 'huge_id.jpg',
        bytes: Uint8List(11 * 1024 * 1024), // 11MB
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: KycDocumentUploadScreen(onPickFile: oversizedPicker),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upload Document').first);
    await tester.pumpAndSettle();

    // Network call should NOT be made
    expect(mockAuth.uploadDocumentCalled, isFalse);
    expect(
        find.textContaining('File size exceeds maximum allowed size of 10MB'),
        findsOneWidget);

    // 2. Test Wrong Format File (e.g. .txt or .pdf for non-pdf slot)
    Future<PickedDocumentFile?> wrongFormatPicker(
        BuildContext context, String slotKey, bool allowPdf) async {
      return PickedDocumentFile(
        filename: 'document.txt',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: KycDocumentUploadScreen(
              key: const ValueKey('wrong_format'),
              onPickFile: wrongFormatPicker),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upload Document').first);
    await tester.pumpAndSettle();

    expect(mockAuth.uploadDocumentCalled, isFalse);
    expect(find.textContaining('Invalid file format. Only JPEG and PNG'),
        findsOneWidget);
  });

  testWidgets('(d) Rejected status shows the rejection reason',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final rejectedUser = UserProfile(
      id: 'owner-102',
      email: 'owner@test.com',
      username: 'testowner',
      role: 'owner',
      kycStatus: 'rejected',
      rejectionReason:
          'ID card image is blurry and illegible. Please re-upload.',
    );
    final mockAuth = MockAuthProvider(apiClient, initialUser: rejectedUser);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: const KycDocumentUploadScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('REJECTED'), findsOneWidget);
    expect(
        find.text(
            'Rejection Reason: ID card image is blurry and illegible. Please re-upload.'),
        findsOneWidget);
  });

  testWidgets('(e) Approved status disables/locks upload actions',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final approvedUser = UserProfile(
      id: 'owner-103',
      email: 'owner@test.com',
      username: 'testowner',
      role: 'owner',
      kycStatus: 'approved',
      idFrontDoc: 'kyb/owner-103/id_front.jpg',
      idBackDoc: 'kyb/owner-103/id_back.jpg',
      selfieDoc: 'kyb/owner-103/selfie.jpg',
      businessProofDoc: 'kyb/owner-103/business_proof.pdf',
    );
    final mockAuth = MockAuthProvider(apiClient, initialUser: approvedUser);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: const KycDocumentUploadScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APPROVED'), findsOneWidget);
    expect(find.text('Documents are locked because your account is approved.'),
        findsOneWidget);

    // Upload / Replace buttons should NOT be present when approved
    expect(find.text('Upload Document'), findsNothing);
    expect(find.text('Replace Document'), findsNothing);
  });

  testWidgets(
      '(f) Content is fully scrollable on 360x800 viewport without nested scroll freeze',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final apiClient = ApiClient();
    final rejectedUser = UserProfile(
      id: 'owner-scroll',
      email: 'owner@test.com',
      username: 'testowner',
      role: 'owner',
      kycStatus: 'rejected',
      rejectionReason:
          'The provided business registration is expired and illegible. Please provide a clear updated copy.',
    );
    final mockAuth = MockAuthProvider(apiClient, initialUser: rejectedUser);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: const KycDocumentUploadScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify there is exactly ONE Scrollable container (no conflicting nested scrollviews)
    final scrollables = find.byType(Scrollable);
    expect(scrollables, findsOneWidget);

    final scrollState = tester.state<ScrollableState>(scrollables.first);
    expect(scrollState.position.pixels, 0.0);
    expect(scrollState.position.maxScrollExtent, greaterThan(0.0));

    // Dragging down scrolls content without getting frozen at 0.0
    await tester.drag(find.byKey(const ValueKey('btn_upload_id_front')),
        const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(scrollState.position.pixels, greaterThan(0.0));

    // Last slot (business proof) is reachable via scroll
    final lastSlotFinder =
        find.byKey(const ValueKey('btn_upload_business_proof'));
    await tester.ensureVisible(lastSlotFinder);
    await tester.pumpAndSettle();
    expect(lastSlotFinder, findsOneWidget);
  });

  testWidgets(
      '(g) Uploaded document image preview uses bounded cacheWidth and cacheHeight',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockAuth = MockAuthProvider(apiClient, initialUser: ownerUser);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: KycDocumentUploadScreen(
            onPickFile: (context, slotKey, allowPdf) async {
              // 1x1 transparent PNG bytes
              return PickedDocumentFile(
                filename: 'passport.png',
                bytes: Uint8List.fromList([
                  0x89,
                  0x50,
                  0x4E,
                  0x47,
                  0x0D,
                  0x0A,
                  0x1A,
                  0x0A,
                  0x00,
                  0x00,
                  0x00,
                  0x0D,
                  0x49,
                  0x48,
                  0x44,
                  0x52,
                  0x00,
                  0x00,
                  0x00,
                  0x01,
                  0x00,
                  0x00,
                  0x00,
                  0x01,
                  0x08,
                  0x06,
                  0x00,
                  0x00,
                  0x00,
                  0x1F,
                  0x15,
                  0xC4,
                  0x89,
                  0x00,
                  0x00,
                  0x00,
                  0x0A,
                  0x49,
                  0x44,
                  0x41,
                  0x54,
                  0x78,
                  0x9C,
                  0x63,
                  0x00,
                  0x01,
                  0x00,
                  0x00,
                  0x05,
                  0x00,
                  0x01,
                  0x0D,
                  0x0A,
                  0x2D,
                  0xB4,
                  0x00,
                  0x00,
                  0x00,
                  0x00,
                  0x49,
                  0x45,
                  0x4E,
                  0x44,
                  0xAE,
                  0x42,
                  0x60,
                  0x82,
                ]),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap upload for front ID
    await tester.tap(find.byKey(const ValueKey('btn_upload_id_front')));
    await tester.pumpAndSettle();

    // Verify Image.memory widget has bounded cache dimensions to prevent decode jank
    final imageFinder = find.byType(Image);
    expect(imageFinder, findsOneWidget);
    final imageWidget = tester.widget<Image>(imageFinder);
    expect(imageWidget.image, isA<ResizeImage>());
    final resizeImage = imageWidget.image as ResizeImage;
    expect(resizeImage.width, equals(144));
    expect(resizeImage.height, equals(144));
  });

  group('Audit A4/A9/A10 findings', () {
    Future<void> pumpKyc(WidgetTester tester, AuthProvider mockAuth) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChangeNotifierProvider<AuthProvider>.value(
            value: mockAuth,
            child: const KycDocumentUploadScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
        '(A9) only the first incomplete slot keeps the focal Upload button',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      final mockAuth = MockAuthProvider(apiClient, initialUser: ownerUser);
      await pumpKyc(tester, mockAuth);

      // Fresh owner: nothing uploaded — id_front is focal Primary, the
      // other three Upload buttons are demoted outlined Secondaries.
      tester.widget<PrimaryButton>(
          find.byKey(const ValueKey('btn_upload_id_front')));
      for (final key in ['id_back', 'selfie', 'business_proof']) {
        final button = tester
            .widget<SecondaryButton>(find.byKey(ValueKey('btn_upload_$key')));
        expect(button.isOutlined, isTrue);
      }
      // Same button text everywhere — only the visual weight changed.
      expect(find.text('Upload Document'), findsNWidgets(4));
    });

    testWidgets('(A4) refresh failure surfaces a retryable banner, then clears',
        (WidgetTester tester) async {
      final mockApi = _KycRefreshMockApiClient();
      final auth = AuthProvider(mockApi);
      // Arm the token + user via a successful login so the post-frame
      // fetchUserProfile actually fires (it early-returns without a token).
      final devOtp = await auth.login('employee@test.com', 'pw');
      expect(devOtp, isNull);
      expect(auth.user, isNotNull);

      await pumpKyc(tester, auth);

      // The profile refresh failed: banner with retry, stale slots intact.
      expect(find.byKey(const Key('kyc_refresh_error_banner')), findsOneWidget);
      expect(mockApi.profileGetCalls, 1);

      // Retry re-fires the fetch; now let it succeed and watch the banner go.
      mockApi.failProfileFetch = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(mockApi.profileGetCalls, 2);
      expect(find.byKey(const Key('kyc_refresh_error_banner')), findsNothing);
    });

    testWidgets('(A10) refresh shows a busy spinner and refuses re-trigger',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      final mockAuth =
          _GatedRefreshMockAuthProvider(apiClient, initialUser: ownerUser);
      mockAuth.refreshGate = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChangeNotifierProvider<AuthProvider>.value(
            value: mockAuth,
            child: const KycDocumentUploadScreen(),
          ),
        ),
      );
      // Post-frame auto-refresh is now in flight behind the held gate.
      await tester.pump();
      await tester.pump();

      expect(mockAuth.refreshCalls, 1);
      expect(find.byKey(const ValueKey('kyc_refresh_busy')), findsOneWidget);
      expect(find.byKey(const Key('kyc_refresh_button')), findsNothing);

      mockAuth.refreshGate!.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('kyc_refresh_busy')), findsNothing);
      expect(find.byKey(const Key('kyc_refresh_button')), findsOneWidget);
    });
  });
}
