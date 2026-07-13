import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final ownerProvider = Provider.of<OwnerProvider>(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: ownerProvider.isLoading && ownerProvider.ledgerEntries.isEmpty && ownerProvider.walletBalance == 0.0
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await ownerProvider.fetchDashboardData(auth.token!);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "My Wallet",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _showDepositDialog(context),
                          icon: const Icon(Icons.add_card_rounded),
                          label: const Text("Deposit Funds"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Balance Display Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildBalanceCard(
                            title: "Total Balance",
                            value: ownerProvider.walletBalance,
                            icon: Icons.account_balance_rounded,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildBalanceCard(
                            title: "Withdrawable",
                            value: ownerProvider.withdrawableBalance,
                            icon: Icons.check_circle_outline_rounded,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildBalanceCard(
                            title: "Locked (Escrow)",
                            value: ownerProvider.escrowBalance,
                            icon: Icons.lock_outline_rounded,
                            color: Colors.amber.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Transaction History Section
                    const Text(
                      "Transaction Ledger",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (ownerProvider.ledgerEntries.isEmpty)
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text(
                                  "No transactions recorded yet.",
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: ownerProvider.ledgerEntries.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          // The ledger list returned is already in chronological order or reverse.
                          // Ensure we render it as-is (we can reverse it on display if the backend is oldest-first).
                          // Usually GetLedger fetches all entries ordered by timestamp. Let's render as retrieved.
                          final entry = ownerProvider.ledgerEntries[index];
                          return _buildLedgerTile(entry);
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBalanceCard({
    required String title,
    required double value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.08), color.withOpacity(0.02)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                Icon(icon, color: color, size: 24),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "${value.toStringAsFixed(2)} Credits",
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgerTile(Map<String, dynamic> entry) {
    final type = entry['type'] ?? '';
    final amount = (entry['amount'] as num?)?.toDouble() ?? 0.0;
    final balanceAfter = (entry['balance_after'] as num?)?.toDouble() ?? 0.0;
    final description = entry['description'] ?? '';
    final jobId = entry['job_id'] ?? '';
    
    DateTime? timestamp;
    if (entry['timestamp'] != null) {
      try {
        timestamp = DateTime.parse(entry['timestamp']).toLocal();
      } catch (_) {}
    }

    IconData icon;
    Color color;

    switch (type) {
      case 'deposit':
        icon = Icons.add_circle_outline_rounded;
        color = Colors.green;
        break;
      case 'escrow_lock':
        icon = Icons.lock_outline_rounded;
        color = Colors.orange;
        break;
      case 'escrow_release':
        icon = Icons.lock_open_rounded;
        color = Colors.blue;
        break;
      case 'refund':
        icon = Icons.replay_rounded;
        color = Colors.teal;
        break;
      case 'fee_deduction':
        icon = Icons.remove_circle_outline_rounded;
        color = Colors.red;
        break;
      default:
        icon = Icons.monetization_on_outlined;
        color = Colors.grey;
    }

    final dateStr = timestamp != null
        ? "${timestamp.year}-${_twoDigits(timestamp.month)}-${_twoDigits(timestamp.day)} ${_twoDigits(timestamp.hour)}:${_twoDigits(timestamp.minute)}"
        : "";

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              radius: 20,
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description.isNotEmpty ? description : type.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      if (jobId.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "Job: ${jobId.substring(0, jobId.length > 8 ? 8 : jobId.length)}",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.indigo.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "${type == 'deposit' || type == 'refund' || type == 'escrow_release' ? '+' : '-'}${amount.toStringAsFixed(2)}",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: type == 'deposit' || type == 'refund' || type == 'escrow_release'
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Bal: ${balanceAfter.toStringAsFixed(2)}",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _twoDigits(int n) => n >= 10 ? "$n" : "0$n";

  void _showDepositDialog(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);
    final amountController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? dialogError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Text(
                "Deposit Funds",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Enter the amount in credits to deposit to your wallet.",
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Amount (Credits)",
                        prefixText: "\$ ",
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "Amount is required";
                        }
                        final amount = double.tryParse(value);
                        if (amount == null || amount <= 0) {
                          return "Please enter a valid positive number";
                        }
                        if (amount > 1000000) {
                          return "Maximum single deposit is 1,000,000 credits";
                        }
                        return null;
                      },
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red.shade200),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dialogError!,
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() {
                              isSubmitting = true;
                              dialogError = null;
                            });

                            try {
                              final amount = double.parse(amountController.text);
                              await ownerProvider.deposit(auth.token!, amount);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Successfully deposited ${amount.toStringAsFixed(2)} credits."),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              setDialogState(() {
                                isSubmitting = false;
                                final errMsg = e.toString();
                                if (errMsg.contains("payment gateway not yet integrated")) {
                                  dialogError = "Deposits aren't available yet — payment gateway integration pending";
                                } else {
                                  dialogError = errMsg;
                                }
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text("Confirm"),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
