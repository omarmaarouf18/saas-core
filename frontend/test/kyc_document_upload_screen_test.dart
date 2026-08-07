import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/kyc_document_upload_screen.dart';

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

void main() {
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
    expect(find.text('Uploaded'), findsWidgets);
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
}
