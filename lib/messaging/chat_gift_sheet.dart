
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/theme.dart';
import '../service.dart';

void showChatGiftSheet(
  BuildContext context, {
  required String otherUid,
  required String otherUserName,
  required String conversationId,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ChatGiftSheet(otherUid: otherUid, otherUserName: otherUserName, conversationId: conversationId),
  );
}

class _ChatGiftSheet extends StatefulWidget {
  final String otherUid;
  final String otherUserName;
  final String conversationId;
  const _ChatGiftSheet({required this.otherUid, required this.otherUserName, required this.conversationId});

  @override
  State<_ChatGiftSheet> createState() => _ChatGiftSheetState();
}

class _ChatGiftSheetState extends State<_ChatGiftSheet> {
  Map<String, dynamic>? _selectedGift;
  int _quantity = 1;
  bool _isSending = false;

  Future<void> _send() async {
    if (_selectedGift == null || _isSending) return;
    setState(() { _isSending = true; });

    try {
      final gift = _selectedGift!['gifts'] as Map<String, dynamic>;
      final giftId = _selectedGift!['giftId'] ?? gift['id'];

      await Supabase.instance.client.rpc('send_gift_to_user', params: {
        'p_gift_id': giftId,
        'p_target_uid': widget.otherUid,
        'p_quantity': _quantity,
      });

      final giftName = gift['name'] ?? 'a gift';
      final giftImageUrl = gift['gifUrl'] as String?;
      try {
        await Supabase.instance.client.rpc('send_message', params: {
          'p_conversation_id': widget.conversationId,
          'p_text': _quantity > 1 ? "🎁 Sent $giftName x$_quantity" : "🎁 Sent $giftName",
          'p_image_url': giftImageUrl,
          'p_reply_to_message_id': null,
        });
      } catch (e) {
        debugPrint("Gift chat-message insert failed (gift itself was still sent): $e");
      }

      Supabase.instance.client
          .rpc('mark_conversation_read', params: {'p_conversation_id': widget.conversationId})
          .catchError((e) => debugPrint('mark_conversation_read failed: $e'));

      sendNotification(targetOwnerId: widget.otherUid, type: 'message', message: 'Someone sent you a gift 🎁');

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gift sent to ${widget.otherUserName}! 🎁")),
        );
      }
    } catch (e) {
      debugPrint("send_gift_to_user failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't send gift: $e"), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() { _isSending = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text("Send a Gift", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox.shrink(),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: Supabase.instance.client
                      .from('gift_inventory')
                      .select('*, gifts(*)')
                      .eq('ownerUid', uid)
                      .eq('source', 'purchased')
                      .gt('count', 0),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final rows = snapshot.data ?? [];
                    final now = DateTime.now();
                    final available = rows.where((r) {
                      final expiresAt = r['expiresAt'];
                      if (expiresAt == null) return true;
                      return DateTime.parse(expiresAt.toString()).isAfter(now);
                    }).toList();

                    final Map<String, Map<String, dynamic>> grouped = {};
                    for (final row in available) {
                      final gift = row['gifts'] as Map<String, dynamic>?;
                      if (gift == null) continue;
                      final giftId = gift['id'] as String;
                      grouped.putIfAbsent(giftId, () => {'gifts': gift, 'giftId': giftId, 'count': 0});
                      grouped[giftId]!['count'] = (grouped[giftId]!['count'] as int) + (row['count'] as int);
                    }

                    if (grouped.isEmpty) {
                      return const Center(
                        child: Text("No purchase gifts in your Bag yet — buy a gift to send it in chat.", textAlign: TextAlign.center),
                      );
                    }

                    final entries = grouped.values.toList();
                    return GridView.builder(
                      controller: scrollController,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final gift = entry['gifts'] as Map<String, dynamic>;
                        final isSelected = _selectedGift != null && _selectedGift!['giftId'] == entry['giftId'];

                        return GestureDetector(
                          onTap: () => setState(() { _selectedGift = entry; _quantity = 1; }),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.accent.withOpacity(0.2) : AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(10),
                              border: isSelected ? Border.all(color: AppColors.accent, width: 2) : null,
                            ),
                            padding: const EdgeInsets.all(6),
                            child: Column(
                              children: [
                                Expanded(child: GlobalCachedImage(imageUrl: gift['gifUrl'] ?? '', fit: BoxFit.contain)),
                                Text(gift['name'] ?? '', style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text("x${entry['count']}", style: const TextStyle(fontSize: 9, color: AppColors.textTertiary)),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (_selectedGift != null) ...[
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: "Decrease quantity",
                      onPressed: _quantity > 1 ? () => setState(() { _quantity--; }) : null,
                    ),
                    Text("$_quantity", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: "Increase quantity",
                      onPressed: (_quantity < (_selectedGift!['count'] as int))
                          ? () => setState(() { _quantity++; })
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _isSending ? null : _send,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
                    child: _isSending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text("Send to ${widget.otherUserName}"),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
