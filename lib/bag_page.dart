
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/theme.dart';
import 'service.dart';
import 'utils.dart';
import 'chests/chests_page.dart';

class BagPage extends StatefulWidget {
  final String? viewUid;
  final int initialTabIndex;

  const BagPage({super.key, this.viewUid, this.initialTabIndex = 0});

  @override
  State<BagPage> createState() => _BagPageState();
}

class _BagPageState extends State<BagPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool get _isOwnBag => widget.viewUid == null;
  String get _uid => widget.viewUid ?? Supabase.instance.client.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isOwnBag
            ? const Text("Bag")
            : FutureBuilder<Map<String, dynamic>?>(
                future: Supabase.instance.client.from('public_profiles').select('userName').eq('uid', _uid).maybeSingle(),
                builder: (context, snapshot) => Text("${snapshot.data?['userName'] ?? 'User'}'s Bag"),
              ),
        actions: [
          if (_isOwnBag)
            TextButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ChestsPage()));
              },
              icon: const Icon(Icons.storefront_outlined, color: AppColors.accent),
              label: const Text("Buy Gifts", style: TextStyle(color: AppColors.accent)),
            ),
        ],
        bottom: _isOwnBag
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: "Owned"),
                  Tab(text: "Received"),
                ],
              )
            : null,
      ),
      body: _isOwnBag
          ? TabBarView(
              controller: _tabController,
              children: [
                _OwnedGiftsTab(uid: _uid),
                _ReceivedGiftsTab(uid: _uid),
              ],
            )
          : _ReceivedGiftsTab(uid: _uid),
    );
  }
}

class _OwnedGiftsTab extends StatelessWidget {
  final String uid;
  const _OwnedGiftsTab({required this.uid});

  Future<List<Map<String, dynamic>>> _loadRows(String source) {
    var query = Supabase.instance.client
        .from('gift_inventory')
        .select('*, gifts(*)')
        .eq('ownerUid', uid)
        .gt('count', 0);

    if (source == 'free') {
      query = query.neq('source', 'purchased');
    } else {
      query = query.eq('source', 'purchased');
    }

    return query.order('expiresAt', ascending: true, nullsFirst: false);
  }

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return const Center(child: Text("Please log in."));

    return Column(
      children: [
        Expanded(child: _GiftInventorySection(uid: uid, source: 'free', title: 'Free Gifts')),
        const Divider(height: 1),
        Expanded(child: _GiftInventorySection(uid: uid, source: 'purchased', title: 'Purchase Gifts')),
      ],
    );
  }
}

class _GiftInventorySection extends StatelessWidget {
  final String uid;
  final String source;
  final String title;

  const _GiftInventorySection({
    required this.uid,
    required this.source,
    required this.title,
  });

  Future<List<Map<String, dynamic>>> _loadRows() {
    var query = Supabase.instance.client
        .from('gift_inventory')
        .select('*, gifts(*)')
        .eq('ownerUid', uid)
        .gt('count', 0);

    query = source == 'free'
        ? query.neq('source', 'purchased')
        : query.eq('source', 'purchased');

    return query.order('expiresAt', ascending: true, nullsFirst: false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadRows(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            children: [
              _sectionHeader(title),
              const Expanded(child: Center(child: CircularProgressIndicator())),
            ],
          );
        }

        final allRows = snapshot.data ?? [];
        final now = DateTime.now();
        final rows = allRows.where((r) {
          final expiresAt = r['expiresAt'];
          if (expiresAt == null) return true;
          return DateTime.parse(expiresAt.toString()).isAfter(now);
        }).toList();

        final Map<String, Map<String, dynamic>> grouped = {};
        for (final row in rows) {
          final gift = row['gifts'] as Map<String, dynamic>?;
          if (gift == null) continue;
          final giftId = gift['id'] as String;
          grouped.putIfAbsent(giftId, () => {
                'gift': gift,
                'count': 0,
                'soonestExpiry': row['expiresAt'],
              });
          grouped[giftId]!['count'] =
              (grouped[giftId]!['count'] as int) + (row['count'] as int);
        }

        return Column(
          children: [
            _sectionHeader(title),
            Expanded(
              child: grouped.isEmpty
                  ? Center(
                      child: Text(
                        source == 'free'
                            ? "No free gifts yet — open a chest or claim a reward."
                            : "No purchase gifts yet — buy some from the Gift Shop.",
                        textAlign: TextAlign.center,
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: grouped.length,
                      itemBuilder: (context, index) {
                        final entry = grouped.values.elementAt(index);
                        final gift = entry['gift'] as Map<String, dynamic>;
                        final count = entry['count'] as int;
                        final expiresAt = entry['soonestExpiry'];

                        return Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              Expanded(
                                child: GlobalCachedImage(
                                  imageUrl: gift['gifUrl'] ?? '',
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                gift['name'] ?? '',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                "x$count",
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                              if (expiresAt != null)
                                _ExpiryCountdown(
                                  expiresAt:
                                      DateTime.parse(expiresAt.toString()),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ExpiryCountdown extends StatefulWidget {
  final DateTime expiresAt;
  const _ExpiryCountdown({required this.expiresAt});

  @override
  State<_ExpiryCountdown> createState() => _ExpiryCountdownState();
}

class _ExpiryCountdownState extends State<_ExpiryCountdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      return const Text("Expired", style: TextStyle(fontSize: 9, color: AppColors.error));
    }
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    return Text(
      "Expires in ${hours}h ${minutes}m",
      style: const TextStyle(fontSize: 9, color: AppColors.error),
      maxLines: 1,
    );
  }
}

class _ReceivedGiftsTab extends StatelessWidget {
  final String uid;
  const _ReceivedGiftsTab({required this.uid});

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return const Center(child: Text("Please log in."));

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('gift_received_log')
          .select('*, gifts(*)')
          .eq('recipientUid', uid)
          .order('createdAt', ascending: false)
          .limit(100),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text("No gifts received yet.", textAlign: TextAlign.center),
            ),
          );
        }

        final fromUids = rows.map((r) => r['fromUid'] as String).toSet().toList();

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: Supabase.instance.client.from('public_profiles').select().inFilter('uid', fromUids),
          builder: (context, sendersSnapshot) {
            final senderProfiles = {
              for (final p in (sendersSnapshot.data ?? [])) p['uid'] as String: p,
            };

            return ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final gift = row['gifts'] as Map<String, dynamic>?;
                final fromUid = row['fromUid'] as String;
                final quantity = row['quantity'];
                final createdAt = row['createdAt'];
                final senderName = senderProfiles[fromUid]?['userName'] ?? 'Someone';

                return ListTile(
                  leading: SizedBox(
                    width: 40,
                    child: GlobalCachedImage(imageUrl: gift?['gifUrl'] ?? '', fit: BoxFit.contain),
                  ),
                  title: Text("${gift?['name'] ?? 'Gift'} x$quantity"),
                  subtitle: Text("From $senderName • ${formatRelativeTimestamp(createdAt)}"),
                );
              },
            );
          },
        );
      },
    );
  }
}
