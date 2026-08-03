import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import 'primary_button.dart';
import 'secondary_button.dart';
import 'themed_error_banner.dart';
import 'themed_text_field.dart';

class CreateTicketDialog extends StatefulWidget {
  final String contextId;

  const CreateTicketDialog({
    super.key,
    required this.contextId,
  });

  @override
  State<CreateTicketDialog> createState() => _CreateTicketDialogState();
}

class _CreateTicketDialogState extends State<CreateTicketDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final chat = Provider.of<ChatProvider>(context, listen: false);

    final subject = _subjectController.text.trim();
    final description = _descriptionController.text.trim();
    final combinedContext = "Job #${widget.contextId} - $subject: $description";

    try {
      final res = await chat.createTicket(
        contextId: combinedContext,
        userToken: auth.token ?? '',
      );

      if (mounted) {
        Navigator.of(context).pop(res);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Ticket submitted successfully! (Ticket ID: ${res['id'] ?? ''})",
            ),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = friendlyErrorMessage(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Open Complaint Ticket"),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Reference ID: #${widget.contextId.length > 8 ? widget.contextId.substring(0, 8) : widget.contextId}",
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_errorMessage != null) ...[
                ThemedErrorBanner(
                  key: const Key('create_ticket_error_banner'),
                  message: _errorMessage!,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              ThemedTextField(
                key: const Key('ticket_subject_input'),
                controller: _subjectController,
                labelText: "Subject / Topic",
                hintText: "e.g. Delayed Delivery / Driver Unresponsive",
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return "Subject is required.";
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              ThemedTextField(
                key: const Key('ticket_description_input'),
                controller: _descriptionController,
                labelText: "Issue Details",
                hintText: "Please describe what went wrong...",
                maxLines: 3,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return "Issue details are required.";
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        SecondaryButton(
          text: "Cancel",
          isOutlined: true,
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        ),
        SizedBox(
          width: 130,
          child: PrimaryButton(
            key: const Key('submit_ticket_button'),
            text: "Submit",
            isLoading: _isSubmitting,
            onPressed: _isSubmitting ? null : _submitTicket,
          ),
        ),
      ],
    );
  }
}
