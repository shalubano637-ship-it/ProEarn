
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/theme.dart';
import 'models.dart';
import 'service.dart';
import 'user_profile_features.dart';
import 'widgets/error_retry_view.dart';
import 'messaging/room_chat_page.dart';

enum _Period { yesterday, today, allTime }
enum _Metric { popularity, gets, likes, room }

class _RankedUser {
  final String uid;
  final String userName;
  final String profileUrl;
  final String bio;
  final num score;
  final int rank;
  final int? rankDelta; // positive = moved up vs previous period
  final String? roomId;
  final int? roomNumber;
  final bool isPrivateRoom;

  _RankedUser({
    required this.uid,
    required this.userName,
    required this.profileUrl,
    required this.bio,
    required this.score,
    required this.rank,
    required this.rankDelta,
    this.roomId,
    this.roomNumber,
    this.isPrivateRoom = false,
  });

  bool get isRoom => roomId != null;
}

class _OwnRank {
  final int rank;
  final num score;
  final int totalRanked;
  final String? roomId;
  final String? roomName;
  final int? roomNumber;

  _OwnRank({
    required this.rank,
    required this.score,
    required this.totalRanked,
    this.roomId,
    this.roomName,
    this.roomNumber,
  });

  int get percentile {
    if (totalRanked <= 0) return 100;
    return ((rank / totalRanked) * 100).ceil().clamp(1, 100);
  }
}

void _openProfile(BuildContext context, String uid) {
  final myUid = Supabase.instance.client.auth.currentUser?.id;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ProfilePage(isOwnProfile: uid == myUid, otherUser: uid == myUid ? null : uid),
    ),
  );
}

Future<String> _istDate(int daysAgo) async {
  final today = await Supabase.instance.client.rpc('ist_today') as String;
  final date = DateTime.parse(today).subtract(Duration(days: daysAgo));
  return "${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
}

Future<List<String>> _rankedUidsForDay(String istDate) async {
  final rows = await Supabase.instance.client
      .from('daily_popularity_counts')
      .select('uid')
      .eq('istDate', istDate)
      .order('popularity', ascending: false)
      .limit(200);
  return rows.map((r) => r['uid'] as String).toList();
}

Future<List<_RankedUser>> _fetchRoomLeaderboard(_Period period) async {
  final periodName = switch (period) {
    _Period.today => 'today',
    _Period.yesterday => 'yesterday',
    _Period.allTime => 'all_time',
  };

  final rows = List<Map<String, dynamic>>.from(
    await Supabase.instance.client.rpc(
      'get_room_leaderboard',
      params: {'p_period': periodName, 'p_limit': 50},
    ) as List,
  );

  List<Map<String, dynamic>> previousRows = const [];
  if (period != _Period.allTime) {
    final previousPeriod = period == _Period.today ? 'yesterday' : 'day_before_yesterday';
    previousRows = List<Map<String, dynamic>>.from(
      await Supabase.instance.client.rpc(
        'get_room_leaderboard',
        params: {'p_period': previousPeriod, 'p_limit': 200},
      ) as List,
    );
  }

  final previousRank = <String, int>{
    for (var i = 0; i < previousRows.length; i++)
      previousRows[i]['room_id'].toString(): i + 1,
  };

  return List.generate(rows.length, (index) {
    final row = rows[index];
    final roomId = row['room_id'].toString();
    final rank = index + 1;
    final previous = previousRank[roomId];
    return _RankedUser(
      uid: row['owner_uid'].toString(),
      userName: row['room_name']?.toString() ?? 'Room',
      profileUrl: row['profile_url']?.toString() ?? '',
      bio: '#${row['room_number']} • ${row['owner_name'] ?? 'User'}',
      score: (row['score'] ?? 0) as num,
      rank: rank,
      rankDelta: previous == null ? null : previous - rank,
      roomId: roomId,
      roomNumber: (row['room_number'] as num?)?.toInt(),
      isPrivateRoom: row['private_room'] == true,
    );
  });
}

Future<_OwnRank?> _fetchOwnRoomRank(_Period period) async {
  final myUid = Supabase.instance.client.auth.currentUser?.id;
  if (myUid == null) return null;

  final periodName = switch (period) {
    _Period.today => 'today',
    _Period.yesterday => 'yesterday',
    _Period.allTime => 'all_time',
  };

  final rows = List<Map<String, dynamic>>.from(
    await Supabase.instance.client.rpc(
      'get_room_leaderboard',
      params: {'p_period': periodName, 'p_limit': 1000},
    ) as List,
  );

  final index = rows.indexWhere((r) => r['owner_uid']?.toString() == myUid);
  if (index == -1) return null;

  final row = rows[index];
  return _OwnRank(
    rank: index + 1,
    score: (row['score'] ?? 0) as num,
    totalRanked: rows.length,
    roomId: row['room_id']?.toString(),
    roomName: row['room_name']?.toString(),
    roomNumber: (row['room_number'] as num?)?.toInt(),
  );
}

Future<void> _openRoomFromLeaderboard(BuildContext context, _RankedUser room) async {
  if (room.roomId == null) return;
  String password = '';

  final currentUid = Supabase.instance.client.auth.currentUser?.id;
  final isOwner = currentUid != null && currentUid == room.uid;

  if (room.isPrivateRoom && !isOwner) {
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Private Room'),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Enter')),
          ],
        );
      },
    );
    if (entered == null) return;
    password = entered;
  }

  try {
    final result = await Supabase.instance.client.rpc('enter_room', params: {
      'p_room_id': room.roomId,
      'p_password': password.isEmpty ? null : password,
    });
    final row = Map<String, dynamic>.from((result as List).first as Map);
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomChatPage(
          roomId: row['room_id'] as String,
          roomNumber: (row['room_number'] as num).toInt(),
          roomName: row['room_name'] as String,
          ownerUid: row['owner_uid'] as String,
          profileUrl: row['profile_url']?.toString() ?? '',
          hasPassword: row['has_password'] == true,
          memberCount: (row['member_count'] as num?)?.toInt() ?? 0,
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().contains('WRONG_PASSWORD') ? 'Wrong password.' : 'Could not enter Room.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

Future<List<_RankedUser>> _fetchLeaderboard(_Period period, _Metric metric) async {
  if (metric == _Metric.room) return _fetchRoomLeaderboard(period);

  if (metric == _Metric.gets || metric == _Metric.likes) {
    List<Map<String, dynamic>> list;
    if (period != _Period.allTime) {
      final daysAgo = period == _Period.today ? 0 : 1;
      final istDate = await _istDate(daysAgo);
      final rows = await Supabase.instance.client.rpc(
        metric == _Metric.gets ? 'get_leaderboard_by_gets_for_day' : 'get_leaderboard_by_likes_for_day',
        params: {'p_ist_date': istDate, 'p_limit': 50},
      );
      list = List<Map<String, dynamic>>.from(rows as List);
    } else {
      final rows = await Supabase.instance.client.rpc(
        metric == _Metric.gets ? 'get_leaderboard_by_gets' : 'get_leaderboard_by_likes',
        params: {'p_limit': 50},
      );
      list = List<Map<String, dynamic>>.from(rows as List);
    }
    return List.generate(list.length, (index) {
      final row = list[index];
      return _RankedUser(
        uid: row['uid'] as String,
        userName: row['userName'] ?? 'User',
        profileUrl: row['profileUrl'] ?? '',
        bio: (row['bio'] ?? '') as String,
        score: (row['score'] ?? 0) as num,
        rank: index + 1,
        rankDelta: null,
      );
    });
  }

  List<Map<String, dynamic>> rows;
  List<String>? previousRanking;

  if (period == _Period.allTime) {
    final result = await Supabase.instance.client.rpc(
      'get_leaderboard_by_popularity_all_time',
      params: {'p_limit': 50},
    );
    rows = List<Map<String, dynamic>>.from(result as List).map((row) => {
      'uid': row['uid'],
      'userName': row['userName'] ?? 'User',
      'profileUrl': row['profileUrl'] ?? '',
      'bio': row['bio'] ?? '',
      'popularity': row['score'] ?? 0,
    }).toList();
  } else {
    final daysAgo = period == _Period.today ? 0 : 1;
    final istDate = await _istDate(daysAgo);

    final counts = await Supabase.instance.client
        .from('daily_popularity_counts')
        .select()
        .eq('istDate', istDate)
        .order('popularity', ascending: false)
        .limit(50);

    if (counts.isEmpty) {
      rows = [];
    } else {
      final uids = counts.map((r) => r['uid'] as String).toList();
      final profiles = await Supabase.instance.client.from('public_profiles').select().inFilter('uid', uids);
      final profileByUid = {for (final p in profiles) p['uid'] as String: p};

      rows = counts.map((row) {
        final uid = row['uid'] as String;
        final profile = profileByUid[uid];
        return {
          'uid': uid,
          'userName': profile?['userName'] ?? 'User',
          'profileUrl': profile?['profileUrl'] ?? '',
          'bio': profile?['bio'] ?? '',
          'popularity': row['popularity'],
        };
      }).toList();
    }

    try {
      final previousIstDate = await _istDate(daysAgo + 1);
      previousRanking = await _rankedUidsForDay(previousIstDate);
    } catch (_) {
      previousRanking = null;
    }
  }

  return List.generate(rows.length, (index) {
    final row = rows[index];
    final uid = row['uid'] as String;
    final rank = index + 1;
    int? delta;
    if (previousRanking != null) {
      final previousIndex = previousRanking.indexOf(uid);
      if (previousIndex != -1) {
        delta = (previousIndex + 1) - rank; // positive = moved up
      }
    }
    return _RankedUser(
      uid: uid,
      userName: row['userName'] ?? 'User',
      profileUrl: row['profileUrl'] ?? '',
      bio: (row['bio'] ?? '') as String,
      score: (row['popularity'] ?? 0) as num,
      rank: rank,
      rankDelta: delta,
    );
  });
}

Future<_OwnRank?> _fetchOwnRank(_Period period, _Metric metric) async {
  if (metric == _Metric.room) return _fetchOwnRoomRank(period);

  final myUid = Supabase.instance.client.auth.currentUser?.id;
  if (myUid == null) return null;

  final client = Supabase.instance.client;

  if (metric == _Metric.gets || metric == _Metric.likes) {
    List<Map<String, dynamic>> rows;
    if (period != _Period.allTime) {
      final daysAgo = period == _Period.today ? 0 : 1;
      final istDate = await _istDate(daysAgo);
      rows = List<Map<String, dynamic>>.from(
        await client.rpc(
          metric == _Metric.gets ? 'get_leaderboard_by_gets_for_day' : 'get_leaderboard_by_likes_for_day',
          params: {'p_ist_date': istDate, 'p_limit': 1000},
        ) as List,
      );
    } else {
      rows = List<Map<String, dynamic>>.from(
        await client.rpc(
          metric == _Metric.gets ? 'get_leaderboard_by_gets' : 'get_leaderboard_by_likes',
          params: {'p_limit': 1000},
        ) as List,
      );
    }
    final index = rows.indexWhere((r) => r['uid'] == myUid);
    if (index == -1) return null;
    final myScore = (rows[index]['score'] ?? 0) as num;
    return _OwnRank(rank: index + 1, score: myScore, totalRanked: rows.length);
  }

  const cap = 1000;

  if (period == _Period.allTime) {
    final result = await client.rpc(
      'get_leaderboard_by_popularity_all_time',
      params: {'p_limit': cap},
    );
    final rows = List<Map<String, dynamic>>.from(result as List);

    final index = rows.indexWhere((r) => r['uid'] == myUid);
    if (index == -1) return null;
    final myScore = (rows[index]['score'] ?? 0) as num;
    return _OwnRank(rank: index + 1, score: myScore, totalRanked: rows.length);
  } else {
    final daysAgo = period == _Period.today ? 0 : 1;
    final istDate = await _istDate(daysAgo);

    final rows = await client
        .from('daily_popularity_counts')
        .select('uid, popularity')
        .eq('istDate', istDate)
        .order('popularity', ascending: false)
        .limit(cap);

    final index = rows.indexWhere((r) => r['uid'] == myUid);
    if (index == -1) return null; // not ranked yet for this day (no gets received)
    final myScore = (rows[index]['popularity'] ?? 0) as num;
    return _OwnRank(rank: index + 1, score: myScore, totalRanked: rows.length);
  }
}

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  _Period _period = _Period.today;
  _Metric _metric = _Metric.popularity;

  Key _bodyKey = UniqueKey();
  Key _footerKey = UniqueKey();

  void _reload() {
    setState(() {
      _bodyKey = UniqueKey();
      _footerKey = UniqueKey();
    });
  }

  void _handleHorizontalSwipe(bool swipeRight) {
    // Within a metric: Yesterday <-> Today <-> All Time.
    // Crossing a boundary moves to the adjacent metric at Today.
    // Metric order: Popularity -> Gets -> Likes -> Room.
    final periodIndex = _period.index;
    final metricIndex = _metric.index;
    int nextPeriod;
    int nextMetric = metricIndex;

    if (swipeRight) {
      if (periodIndex < _Period.values.length - 1) {
        nextPeriod = periodIndex + 1;
      } else {
        nextPeriod = _Period.today.index;
        nextMetric = (metricIndex + 1) % _Metric.values.length;
      }
    } else {
      if (periodIndex > 0) {
        nextPeriod = periodIndex - 1;
      } else {
        nextPeriod = _Period.today.index;
        nextMetric = (metricIndex - 1 + _Metric.values.length) % _Metric.values.length;
      }
    }

    setState(() {
      _period = _Period.values[nextPeriod];
      _metric = _Metric.values[nextMetric];
      _bodyKey = UniqueKey();
      _footerKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasUser = Supabase.instance.client.auth.currentUser != null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Leaderboard"),
        actions: [
          _MetricToggle(
            selected: _metric,
            onChanged: (m) {
              setState(() {
                _metric = m;
                _bodyKey = UniqueKey();
                _footerKey = UniqueKey();
              });
            },
          ),
          const SizedBox(width: 6),
        ],
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            child: _PeriodToggle(
              selected: _period,
              onChanged: (p) {
                setState(() {
                  _period = p;
                  _bodyKey = UniqueKey();
                  _footerKey = UniqueKey();
                });
              },
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity.abs() < 250) return;
                _handleHorizontalSwipe(velocity < 0);
              },
              child: _LeaderboardBody(key: _bodyKey, period: _period, metric: _metric, onRetry: _reload),
            ),
          ),
          if (hasUser) _OwnRankCard(key: _footerKey, period: _period, metric: _metric),
        ],
      ),
    );
  }
}

class _MetricToggle extends StatelessWidget {
  final _Metric selected;
  final ValueChanged<_Metric> onChanged;

  const _MetricToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 235,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _Metric.values.map((m) {
        final isSelected = m == selected;
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: GestureDetector(
            onTap: () => onChanged(m),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : AppColors.surface,
                borderRadius: AppRadius.pillRadius,
                border: Border.all(color: isSelected ? AppColors.accent : Theme.of(context).colorScheme.outline),
              ),
              child: Text(
                switch (m) {
                  _Metric.popularity => "Popularity",
                  _Metric.gets => "Gets",
                  _Metric.likes => "Likes",
                  _Metric.room => "Room",
                },
                style: AppTextStyles.labelMedium.copyWith(
                  fontSize: 10,
                  color: isSelected ? AppColors.textOnAccent : Theme.of(context).colorScheme.onSurface.withOpacity(0.70),
                ),
              ),
            ),
          ),
        );
          }).toList(),
        ),
      ),
    );
  }
}

class _PeriodToggle extends StatelessWidget {
  final _Period selected;
  final ValueChanged<_Period> onChanged;

  const _PeriodToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.pillRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: _Period.values.map((p) {
          final isSelected = p == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accent : AppColors.transparent,
                  borderRadius: AppRadius.pillRadius,
                ),
                child: Text(
                  switch (p) {
                    _Period.yesterday => "Yesterday",
                    _Period.today => "Today",
                    _Period.allTime => "All Time",
                  },
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: isSelected ? AppColors.textOnAccent : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _LeaderboardBody extends StatelessWidget {
  final _Period period;
  final _Metric metric;
  final VoidCallback onRetry;

  const _LeaderboardBody({super.key, required this.period, required this.metric, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_RankedUser>>(
      future: _fetchLeaderboard(period, metric),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        if (snapshot.hasError) {
          return ErrorRetryView(error: snapshot.error, onRetry: onRetry);
        }

        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          return Center(
            child: Text(
              metric == _Metric.room
                  ? (period == _Period.allTime ? "No Rooms yet." : "No Room visits yet for this day.")
                  : period == _Period.allTime
                      ? "No creators yet."
                      : (metric == _Metric.likes ? "No likes yet for this day." : "No gets yet for this day."),
              style: const TextStyle(color: AppColors.textTertiary),
            ),
          );
        }

        final podium = users.take(3).toList();
        final rest = users.length > 3 ? users.sublist(3) : <_RankedUser>[];

        return ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          children: [
            _PodiumSection(users: podium),
            const SizedBox(height: AppSpacing.lg),
            ...rest.map((u) => _RankRow(user: u)),
          ],
        );
      },
    );
  }
}

class _PodiumSection extends StatelessWidget {
  final List<_RankedUser> users; // up to 3, already rank-ordered

  const _PodiumSection({required this.users});

  _RankedUser? _byRank(int rank) {
    for (final u in users) {
      if (u.rank == rank) return u;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final first = _byRank(1);
    final second = _byRank(2);
    final third = _byRank(3);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: second == null ? const SizedBox.shrink() : _PodiumSpot(user: second, size: _PodiumSize.small)),
          Expanded(flex: 2, child: first == null ? const SizedBox.shrink() : _PodiumSpot(user: first, size: _PodiumSize.large)),
          Expanded(child: third == null ? const SizedBox.shrink() : _PodiumSpot(user: third, size: _PodiumSize.small)),
        ],
      ),
    );
  }
}

enum _PodiumSize { small, large }

class _PodiumSpot extends StatelessWidget {
  final _RankedUser user;
  final _PodiumSize size;

  const _PodiumSpot({required this.user, required this.size});

  Color get _medalColor => switch (user.rank) {
        1 => AppColors.accent,
        2 => AppColors.silver,
        _ => AppColors.bronze,
      };

  double get _avatarDiameter => size == _PodiumSize.large ? 88 : 64;
  double get _badgeDiameter => size == _PodiumSize.large ? 30 : 24;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => user.isRoom ? _openRoomFromLeaderboard(context, user) : _openProfile(context, user.uid),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (user.rank == 1) ...[
            Icon(Icons.emoji_events_rounded, color: _medalColor, size: 28),
            const SizedBox(height: 2),
          ],
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: _avatarDiameter,
                height: _avatarDiameter,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _medalColor, width: 3),
                  boxShadow: user.rank == 1 ? AppElevation.accentGlow : null,
                ),
                child: ClipOval(
                  child: GlobalCachedImage(
                    imageUrl: user.profileUrl,
                    width: _avatarDiameter,
                    height: _avatarDiameter,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                bottom: -6,
                child: Container(
                  width: _badgeDiameter,
                  height: _badgeDiameter,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _medalColor,
                    border: Border.all(color: AppColors.background, width: 2),
                  ),
                  child: Text(
                    "${user.rank}",
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.textOnAccent,
                      fontSize: size == _PodiumSize.large ? 15 : 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            user.isRoom ? user.userName : "@${user.userName}",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelMedium.copyWith(
              color: user.rank == 1 ? _medalColor : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatScore(user.score),
            style: AppTextStyles.bodyMedium.copyWith(
              color: user.rank == 1 ? _medalColor : AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final _RankedUser user;

  const _RankRow({required this.user});

  bool get _hasSubtitle => user.bio.isNotEmpty && user.bio != 'No Bio Yet';

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => user.isRoom ? _openRoomFromLeaderboard(context, user) : _openProfile(context, user.uid),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.mdRadius,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                "${user.rank}",
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textTertiary),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ClipOval(
              child: GlobalCachedImage(imageUrl: user.profileUrl, width: 44, height: 44, fit: BoxFit.cover),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.isRoom ? user.userName : "@${user.userName}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600),
                  ),
                  if (_hasSubtitle)
                    Text(
                      user.bio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatScore(user.score),
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                _RankDelta(delta: user.rankDelta),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RankDelta extends StatelessWidget {
  final int? delta;

  const _RankDelta({required this.delta});

  @override
  Widget build(BuildContext context) {
    if (delta == null) {
      return const Text("NEW", style: TextStyle(color: AppColors.info, fontSize: 11, fontWeight: FontWeight.w600));
    }
    if (delta == 0) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.remove, size: 12, color: AppColors.textTertiary),
          Text(" 0", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55), fontSize: 11)),
        ],
      );
    }
    final up = delta! > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          size: 16,
          color: up ? AppColors.success : AppColors.error,
        ),
        Text(
          "${delta!.abs()}",
          style: TextStyle(color: up ? AppColors.success : AppColors.error, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _OwnRankCard extends StatelessWidget {
  final _Period period;
  final _Metric metric;

  const _OwnRankCard({super.key, required this.period, required this.metric});

  @override
  Widget build(BuildContext context) {
    final myUid = Supabase.instance.client.auth.currentUser?.id;

    return FutureBuilder<_OwnRank?>(
      future: _fetchOwnRank(period, metric),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 0);
        }
        if (snapshot.hasError || myUid == null) {
          return const SizedBox(height: 0);
        }

        final ownRank = snapshot.data;
        if (ownRank == null) {
          return Container(
            margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: AppRadius.lgRadius,
            ),
            child: Text(
              metric == _Metric.room
                  ? (period == _Period.allTime
                      ? "Your Room is not ranked yet — invite people to join."
                      : "Your Room is not ranked for this day yet.")
                  : period == _Period.allTime
                      ? "You're not ranked yet — start earning gets to appear here."
                      : "You're not ranked for this day yet.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.70), fontSize: 13),
            ),
          );
        }

        final isRoom = metric == _Metric.room && ownRank.roomId != null;
        return GestureDetector(
          onTap: isRoom ? null : () => _openProfile(context, myUid),
          child: Container(
            margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: AppRadius.lgRadius,
              boxShadow: AppElevation.raised,
            ),
            child: Row(
              children: [
                Text(
                  "${ownRank.rank}",
                  style: AppTextStyles.h2.copyWith(color: AppColors.textPrimaryLight),
                ),
                const SizedBox(width: AppSpacing.md),
                ClipOval(
                  child: GlobalCachedImage(imageUrl: currentUserProfile, width: 44, height: 44, fit: BoxFit.cover),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRoom
                            ? "${ownRank.roomName ?? 'Your Room'} • #${ownRank.roomNumber ?? ''}"
                            : "You (@$currentUserName)",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: AppRadius.smRadius),
                        child: Text(
                          isRoom ? "ROOM RANK" : "PERSONAL BEST",
                          style: AppTextStyles.caption.copyWith(color: AppColors.accentMuted, fontWeight: FontWeight.w700, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatScore(ownRank.score),
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimaryLight, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      "Top ${ownRank.percentile}%",
                      style: AppTextStyles.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _formatScore(num score) {
  if (score >= 1000000) return "${(score / 1000000).toStringAsFixed(1)}M";
  if (score >= 1000) return "${(score / 1000).toStringAsFixed(1)}K";
  return score.toStringAsFixed(0);
}
