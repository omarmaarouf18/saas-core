import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
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
  final String? contextId;

  const CreateTicketDialog({
    super.key,
    this.contextId,
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
    final hasContextId =
        widget.contextId != null && widget.contextId!.trim().isNotEmpty;
    final combinedContext = hasContextId
        ? "Job #${widget.contextId} - $subject: $description"
        : "$subject: $description";

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
    final l10n = context.l10n;
    final hasContextId =
        widget.contextId != null && widget.contextId!.trim().isNotEmpty;

    return AlertDialog(
      title: Text(l10n.jobStatusOpenTicketBtn),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasContextId) ...[
                Text(
                  "Reference ID: #${widget.contextId!.length > 8 ? widget.contextId!.substring(0, 8) : widget.contextId}",
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
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
                labelText: l10n.settingsCustomerService,
                hintText: l10n.settingsCustomerServiceSub,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return l10n.ticketSubjectReq;
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              ThemedTextField(
                key: const Key('ticket_description_input'),
                controller: _descriptionController,
                labelText: l10n.settingsCustomerServiceSub,
                hintText: l10n.settingsCustomerServiceSub,
                maxLines: 3,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return l10n.ticketDescriptionReq;
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: 100,
          child: SecondaryButton(
            text: l10n.cancel,
            isOutlined: true,
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          ),
        ),
        SizedBox(
          width: 130,
          child: PrimaryButton(
            key: const Key('submit_ticket_button'),
            text: l10n.submit,
            isLoading: _isSubmitting,
            onPressed: _isSubmitting ? null : _submitTicket,
          ),
        ),
      ],
    );
  }
}
