import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/src/rust/api/matrix_client.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

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
  List<RoomTimeline> timeline = [];
  late TextEditingController textEditingController;
  late final Timer timer;
  @override
  void initState() {
    textEditingController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadTimeline(roomId: widget.roomId).listen(
        (items) {
          if (mounted) {
            setState(() {
              if (!timeline.contains(items)) {
                timeline.add(items);
              }
            });
          }
        },
        onError: (error) {
          // Handle error if needed
          print('Error loading timeline: $error');
        },
      );
    });

    Future.delayed(const Duration(seconds: 1), () {
      timelinePaginateBackwards(roomId: widget.roomId);
    });
    super.initState();
  }

  @override
  void dispose() {
    removeTimelineStream(roomId: widget.roomId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.roomName)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              shrinkWrap: false,
              itemCount: timeline.length,
              itemBuilder: (context, index) {
                final message = timeline.reversed.toList()[index];
                return RichText(
                  text: TextSpan(
                    style: MatrixTheme.captionStyle,
                    children: [
                      TextSpan(
                        text:
                            "[${message.sender.replaceAll(':server.serverplatform.ae', '')}] ",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: ': ${message.content}'),
                    ],
                  ),
                );
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
      bottomNavigationBar: SizedBox(height: 40),
    );
  }
}
