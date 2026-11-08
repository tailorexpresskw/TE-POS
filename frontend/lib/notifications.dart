part of 'app.dart';

extension NotificationInbox on AppState {
  Future<void> refreshNotifications({bool quiet = true}) async {
    final user = member['id'];
    if (!authenticated || user == null) return;
    try {
      final data = Json.from(await Api.get('notifications'));
      if (mounted && authenticated && member['id'] == user) {
        update(() {
          notificationItems = AppState.maps(data['items']);
          unreadNotifications = (data['unread'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (e) {
      if (e is ApiException && e.status == 401) {
        update(() => authenticated = false);
      }
      if (!quiet) rethrow;
    }
  }

  Future<void> bindDeviceNotifications() async {
    final user = member['id'];
    try {
      final subscription = await browser.currentPushSubscription();
      if (subscription.isNotEmpty && authenticated && member['id'] == user) {
        await Api.post('notifications/subscriptions', {
          'action': 'subscribe',
          'subscription': jsonDecode(subscription),
        });
      }
    } catch (_) {
      /* The inbox is available even when this device has no push support. */
    }
  }

  Future<void> disableDeviceNotifications() async {
    final subscription = await browser.currentPushSubscription();
    if (subscription.isNotEmpty) {
      final values = Json.from(jsonDecode(subscription));
      await Api.post('notifications/subscriptions', {
        'action': 'unsubscribe',
        'endpoint': values['endpoint'],
      });
      await browser.unsubscribeNotifications();
    }
  }

  Future<void> openNotifications() async {
    if (notificationDialogOpen || !authenticated) return;
    notificationDialogOpen = true;
    try {
      await refreshNotifications(quiet: false);
      final config = Json.from(await Api.get('notifications/config'));
      var device = Json.from(
        jsonDecode(await browser.deviceNotificationState()),
      );
      var saving = false;
      if (!mounted || !authenticated) return;
      await modal(
        'Notifications',
        StatefulBuilder(
          builder: (ctx, set) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Work notifications',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text(
                'New assignments appear for the assigned tailor. Completed and held jobs alert staff in the relevant branch.',
              ),
              const SizedBox(height: 16),
              Text(
                device['subscribed'] == true
                    ? 'Notifications are enabled on this device.'
                    : 'Enable device notifications to receive work alerts when the POS is closed.',
              ),
              if (device['supported'] != true)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Use HTTPS and a supported browser. On iPhone or iPad, add the POS to your Home Screen first.',
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            notice(await browser.installApp());
                          },
                    icon: const Icon(Icons.install_mobile_outlined, size: 17),
                    label: const Text('Install POS app'),
                  ),
                  FilledButton(
                    onPressed:
                        saving ||
                            device['supported'] != true ||
                            config['enabled'] != true
                        ? null
                        : () async {
                            set(() => saving = true);
                            try {
                              if (device['subscribed'] == true) {
                                await disableDeviceNotifications();
                              } else {
                                final result = await browser
                                    .subscribeNotifications(
                                      config['publicKey'],
                                    );
                                try {
                                  await Api.post(
                                    'notifications/subscriptions',
                                    {
                                      'action': 'subscribe',
                                      'subscription': jsonDecode(result),
                                    },
                                  );
                                } catch (_) {
                                  await browser.unsubscribeNotifications();
                                  rethrow;
                                }
                              }
                              device = Json.from(
                                jsonDecode(
                                  await browser.deviceNotificationState(),
                                ),
                              );
                              if (ctx.mounted) set(() => saving = false);
                            } catch (e) {
                              notice(e, error: true);
                              if (ctx.mounted) set(() => saving = false);
                            }
                          },
                    child: Text(
                      saving
                          ? 'Saving…'
                          : device['subscribed'] == true
                          ? 'Disable device alerts'
                          : 'Enable device alerts',
                    ),
                  ),
                ],
              ),
              const Divider(height: 30),
              if (notificationItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No work notifications yet.'),
                ),
              if (notificationItems.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await run(() async {
                      await Api.post('notifications', {
                        'action': 'read',
                        'id': 'all',
                      });
                      await refreshNotifications();
                    });
                    if (ctx.mounted) set(() {});
                  },
                  child: const Text('Mark all as read'),
                ),
              ...notificationItems.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item['type'] == 'assigned'
                        ? Icons.assignment_ind_outlined
                        : item['type'] == 'completed'
                        ? Icons.task_alt
                        : Icons.pause_circle_outline,
                    color: (item['read_at'] ?? '') == '' ? green : muted,
                  ),
                  title: Text(
                    item['title'],
                    style: TextStyle(
                      fontWeight: (item['read_at'] ?? '') == ''
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    '${item['message']}\n${branchLabel(item['branch'])} · ${displayDate(item['created_at'])}',
                  ),
                  isThreeLine: true,
                  onTap: () async {
                    try {
                      await Api.post('notifications', {
                        'action': 'read',
                        'id': item['id'],
                      });
                      await refreshNotifications();
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop();
                      if (isTailor) {
                        await jobDetail({'id': item['order_id']});
                      } else {
                        await receipt({'id': item['order_id']});
                      }
                    } catch (e) {
                      notice(e, error: true);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        width: 580,
      );
    } catch (e) {
      notice(e, error: true);
    } finally {
      notificationDialogOpen = false;
    }
  }
}
