import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';

class RatingScreen extends StatefulWidget {
  final Job job;

  const RatingScreen({super.key, required this.job});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  int _selectedStars = 5;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLoadingOtherStatus = true;
  bool _otherPartyHasRated = false;
  String _otherPartyName = "Marcus J.";
  String _otherPartyRole = "Driver / Specialist";
  String? _otherPartyId;

  @override
  void initState() {
    super.initState();
    _determineParties();
    _checkOtherPartyRatingStatus();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _determineParties() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.user;
    if (user != null) {
      if (user.role == 'employee') {
        // Employee is rating the Owner (customer)
        _otherPartyId = widget.job.ownerId;
        _otherPartyName = "Client / Owner";
        _otherPartyRole = "Owner";
      } else {
        // Owner/Customer is rating the Employee (driver)
        _otherPartyId = widget.job.employeeId;
        _otherPartyName = "Driver / Employee";
        _otherPartyRole = "Specialist";
      }
    }
  }

  Future<void> _checkOtherPartyRatingStatus() async {
    setState(() {
      _isLoadingOtherStatus = true;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final marketplaceProvider = Provider.of<MarketplaceProvider>(context, listen: false);

    try {
      // Fetch ratings received by the current user
      final res = await marketplaceProvider.fetchRatings(auth.token!);
      final list = res['ratings'] as List<dynamic>? ?? [];

      bool found = false;
      for (var item in list) {
        if (item is Map && item['job_id'] == widget.job.id) {
          // If we received a rating for this job from the other party
          if (item['rated_by'] == _otherPartyId) {
            found = true;
            break;
          }
        }
      }

      setState(() {
        _otherPartyHasRated = found;
        _isLoadingOtherStatus = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingOtherStatus = false;
      });
    }
  }

  Future<void> _submitRating() async {
    if (_otherPartyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Error: Cannot determine other party identity."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final marketplaceProvider = Provider.of<MarketplaceProvider>(context, listen: false);

    try {
      await marketplaceProvider.rateJob(
        jobId: widget.job.id,
        ratedByToken: auth.token!,
        ratedUserId: _otherPartyId!,
        stars: _selectedStars,
        comment: _commentController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Blind rating submitted successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        // Refresh the other party status to see if it unlocks
        await _checkOtherPartyRatingStatus();
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Rate Your Experience"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Status",
            onPressed: _checkOtherPartyRatingStatus,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Context Header
            Center(
              child: Column(
                children: [
                  Text(
                    'JOB ID: ${widget.job.id.substring(0, widget.job.id.length > 8 ? 8 : widget.job.id.length).toUpperCase()}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary.withOpacity(0.7),
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rate Your Experience',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      'Ratings are blind. Neither party will see the other\'s feedback until both have submitted.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Main Interactive Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildRatingForm(colorScheme, theme)),
                          const SizedBox(width: 32),
                          Expanded(child: _buildBlindStatusVisualizer(colorScheme, theme)),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildRatingForm(colorScheme, theme),
                          const SizedBox(height: 32),
                          _buildBlindStatusVisualizer(colorScheme, theme),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 32),

            // Information Grid
            GridView.count(
              crossAxisCount: isWide ? 3 : 1,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: isWide ? 1.8 : 3.5,
              children: [
                _buildInfoCard(
                  icon: Icons.security_outlined,
                  title: "Unbiased Reviews",
                  subtitle: "Preventing retaliatory or social-pressure ratings.",
                  colorScheme: colorScheme,
                ),
                _buildInfoCard(
                  icon: Icons.verified_outlined,
                  title: "Trust Shield",
                  subtitle: "Ratings directly impact platform reliability ranks.",
                  colorScheme: colorScheme,
                ),
                _buildInfoCard(
                  icon: Icons.history_toggle_off_outlined,
                  title: "24h Window",
                  subtitle: "Submit within 24 hours to ensure your score counts.",
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingForm(ColorScheme colorScheme, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Driver info row
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.local_shipping,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _otherPartyName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _otherPartyRole,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Score stars
        Text(
          'Score Experience',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurfaceVariant,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(5, (index) {
            final starValue = index + 1;
            final isSelected = starValue <= _selectedStars;
            return IconButton(
              onPressed: () {
                setState(() {
                  _selectedStars = starValue;
                });
              },
              icon: Icon(
                isSelected ? Icons.star : Icons.star_border,
                color: isSelected ? colorScheme.secondary : Colors.grey,
                size: 36,
              ),
            );
          }),
        ),
        const SizedBox(height: 24),

        // Feedback input
        Text(
          'Private Feedback (Optional)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurfaceVariant,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _commentController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: "What went well? What could be improved?",
            border: const OutlineInputBorder(),
            fillColor: colorScheme.surfaceContainerLow,
            filled: true,
          ),
        ),
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitRating,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text(
                  "Submit Blind Rating",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }

  Widget _buildBlindStatusVisualizer(ColorScheme colorScheme, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isLoadingOtherStatus) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text("Loading status..."),
          ] else if (_otherPartyHasRated) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: Colors.green,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Feedback Locked In!",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "The other party has submitted their rating. Both feedbacks are now visible under profile summary.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.visibility_off_outlined,
                  size: 48,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.3),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorScheme.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              "Waiting for other party...",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "The other party has not yet rated this transaction. Your ratings will remain hidden until they submit.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            // Progress Bar
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: colorScheme.outline.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required ColorScheme colorScheme,
  }) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colorScheme.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
