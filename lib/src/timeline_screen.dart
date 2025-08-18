import 'package:flutter/material.dart';
import 'package:matrix/main.dart';
import 'package:matrix/src/rust/matrix/rooms.dart';
import 'package:matrix/src/rust/matrix/timelines.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:provider/provider.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    required this.roomId,
    required this.roomName,
  });
  final String roomId;
  final String roomName;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<Message> timeline = [];
  late TextEditingController textEditingController;
  @override
  void initState() {
    textEditingController = TextEditingController();

    getTimelineItemsByRoomId(roomId: widget.roomId).then((value) {
      if (mounted) {
        setState(() {
          timeline = value;
        });
      }
    });

    Future.delayed(const Duration(seconds: 5), () {
      subscribeToTimelineUpdates(roomId: widget.roomId).listen((event) {
        if (mounted) {
          switch (event.messageUpdateType) {
            case MessageUpdateType.append:
              if (event.messages != null) {
                setState(() {
                  timeline.addAll(event.messages!);
                });
              }
              break;
            case MessageUpdateType.pushFront:
              if (event.messages != null && event.messages!.length == 1) {
                setState(() {
                  timeline.insert(0, event.messages!.first);
                });
              }
              break;
            case MessageUpdateType.remove:
              if (event.index != null) {
                setState(() {
                  timeline.removeAt(event.index!.toInt());
                });
              }
              break;
            case MessageUpdateType.reset:
              if (event.messages != null) {
                setState(() {
                  timeline = event.messages!;
                });
              }
              break;

            case MessageUpdateType.truncate:
              setState(() {
                timeline.removeRange(event.index!.toInt(), timeline.length);
              });

            case MessageUpdateType.set_:
              if (event.index != null &&
                  event.messages != null &&
                  event.messages!.length == 1 &&
                  timeline.length >= event.index!.toInt()) {
                setState(() {
                  timeline[event.index!.toInt()] = event.messages!.first;
                });
              }
              break;

            case MessageUpdateType.insert:
              if (event.index != null &&
                  event.messages != null &&
                  event.messages!.length == 1) {
                setState(() {
                  timeline.insert(event.index!.toInt(), event.messages!.first);
                });
              }
            case MessageUpdateType.popBack:
              setState(() {
                timeline.removeLast();
              });
            case MessageUpdateType.popFront:
              setState(() {
                timeline.removeAt(0);
              });
            case MessageUpdateType.pushBack:
              if (event.messages != null && event.messages!.length == 1) {
                setState(() {
                  timeline.add(event.messages!.first);
                });
              }
              break;
            case MessageUpdateType.clear:
              setState(() {
                timeline.clear();
              });
          }
        }
      });
    });

    super.initState();
  }

  @override
  void dispose() {
    timeline.clear();
    textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.roomName)),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: context.read<ThemeProvider>().backgroundGradient,
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  reverse: true,
                  shrinkWrap: false,
                  itemCount: timeline.length,
                  itemBuilder: (context, index) {
                    final message = timeline.reversed.toList()[index];
                    if (message.messageType == MessageType.message) {
                      return RichText(
                        text: TextSpan(
                          style: MatrixTheme.captionStyle,
                          children: [
                            TextSpan(
                              text: getSenderName(message.sender),
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            TextSpan(text: ' ${message.content}'),
                          ],
                        ),
                      );
                    } else {
                      return SizedBox.shrink();
                    }
                  },
                ),
              ),
              SizedBox(
                height: 60,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: textEditingController,
                          decoration: InputDecoration(
                            hintText: 'Type a message',
                            border: UnderlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () {
                          sendMessage(
                            roomId: widget.roomId,
                            content: textEditingController.text,
                          );
                          textEditingController.clear();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String getSenderName(String sender) {
    final host = homeserverUrl.host;
    return sender.replaceAll(host, '');
  }
}
