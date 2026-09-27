

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../service.dart';
import '../theme/theme.dart';

class BlockedUsersListScreen extends StatelessWidget {
  const BlockedUsersListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final theme = Theme.of(context);

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text("Session expired.")));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Blocked Users")),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client.from(kUsersCollection).stream(primaryKey: ['uid']).eq('uid', currentUser.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Data fetch failed."));
          }

          var userData = snapshot.data!.first;
          List<dynamic> blockedUids = userData['blockedUsers'] ?? [];

          if (blockedUids.isEmpty) {
            return const Center(
              child: Text(
                "You haven't blocked anyone.",
                style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
              ),
            );
          }

          return ListView.builder(
            itemCount: blockedUids.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              String blockedUid = blockedUids[index];

              return FutureBuilder<Map<String, dynamic>?>(
                future: Supabase.instance.client
                    .from('public_profiles')
                    .select()
                    .eq('uid', blockedUid)
                    .maybeSingle(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData || userSnapshot.data == null) {
                    return const SizedBox.shrink(); // User deleted hai to skip karein
                  }

                  var targetData = userSnapshot.data!;
                  String username = targetData['userName'] ?? "Unknown User";
                  String profileUrl = targetData['profileUrl'] ?? "";

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      child: ClipOval(
                        child: GlobalCachedImage(
                          imageUrl: profileUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorWidget: const Icon(Icons.person),
                        ),
                      ),
                    ),
                    title: Text(username, style: const TextStyle(fontWeight: FontWeight.w500)),
                    trailing: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: theme.colorScheme.outline),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlRadius),
                      ),
                      onPressed: () async {
                        await Supabase.instance.client.rpc('unblock_user', params: {
                          'p_user_id': currentUser.id,
                          'p_blocked_id': blockedUid,
                        });

                        
                      },
                      child: const Text("Unblock", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
