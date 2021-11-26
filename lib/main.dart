import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_subtitle/models/subtitle.dart';
import 'package:intl/intl.dart';

typedef void OnError(Exception exception);

void main() {
  runApp(new MaterialApp(home: new Scaffold(body: new AudioApp())));
}

enum PlayerState { stopped, playing, paused }

class AudioApp extends StatefulWidget {
  @override
  _AudioAppState createState() => new _AudioAppState();
}

class _AudioAppState extends State<AudioApp> {
  Duration duration;
  Duration position;

  AudioPlayer audioPlayer;

  String localFilePath;

  PlayerState playerState = PlayerState.stopped;
  List<Subtitle> subTitle = List<Subtitle>();

  get isPlaying => playerState == PlayerState.playing;
  get isPaused => playerState == PlayerState.paused;

  get durationText =>
      duration != null ? duration.toString().split('.').first : '';
  get positionText =>
      position != null ? position.toString().split('.').first : '';

  int millisecondsFromTime(DateTime time) {
    int milliseconds = 0;

    milliseconds = time.hour * 3600000 +
        time.minute * 60000 +
        time.second * 1000 +
        time.millisecond;

    return milliseconds;
  }

  Subtitle currentCaption;
  Subtitle _getCurrentCuption(Duration p) {
    if (p != null) {
      for (var item in subTitle) {
        if (p.inMilliseconds >= millisecondsFromTime(item.begin) &&
            p.inMilliseconds <= millisecondsFromTime(item.end)) {
          return item;
        }
      }
      return null;
    }
  }

  RichText richText;
  RichText _subtitleWordByWord(Subtitle subtitle, Duration currentPosition) {
    var textSpan = <TextSpan>[];

    var words = subtitle.caption.split(' ');
    var begin = millisecondsFromTime(subtitle.begin);
    var end = millisecondsFromTime(subtitle.end);
    int current = currentPosition.inMilliseconds;
    var duration = (end - begin) / subtitle.caption.length;
    int keep = 0;
    var keepBegin = 0;
    for (var word in words) {
      keepBegin = (duration * (word.length + 1)).round();
      if (current >= begin + keep && current <= begin + keep + keepBegin) {
        //print('${begin + keep} -> ${current} -> $end');
        
        textSpan.add(TextSpan(
            text: '$word ',
            style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 30,
                fontWeight: FontWeight.bold)));
      } else {
        textSpan.add(TextSpan(text: '$word '));
      }
      keep += (duration * (word.length + 1)).round();
    }

    return RichText(
      text: TextSpan(
          style: TextStyle(color: Colors.deepPurpleAccent, fontSize: 24.0),
          children: textSpan),
    );
  }

  String _currentPosition() {
    String result = '';
    if (position != null) {
      result = "${positionText ?? ''} / ${durationText ?? ''}";
    } else if (duration != null) {
      result += durationText;
    }
    return result;
  }

  bool isMuted = false;

  StreamSubscription _positionSubscription;
  StreamSubscription _audioPlayerStateSubscription;

  @override
  void initState() {
    super.initState();
    initAudioPlayer();
  }

  @override
  void dispose() {
    _positionSubscription.cancel();
    _audioPlayerStateSubscription.cancel();
    audioPlayer.stop();
    super.dispose();
  }

  void initAudioPlayer() {
    audioPlayer = new AudioPlayer();
    _positionSubscription =
        audioPlayer.onAudioPositionChanged.listen((p) => setState(() {
              position = p;
              this.currentCaption = _getCurrentCuption(p);
              this.richText = _subtitleWordByWord(currentCaption, p);
            }));
    _audioPlayerStateSubscription =
        audioPlayer.onPlayerStateChanged.listen((s) {
      if (s == AudioPlayerState.PLAYING) {
        setState(() {
          audioPlayer.onDurationChanged.listen((Duration d) {
            //print('Max duration: $d');
            setState(() => duration = d);
          });
        });
      } else if (s == AudioPlayerState.STOPPED) {
        onComplete();
        setState(() {
          position = duration;
        });
      }
    }, onError: (msg) {
      setState(() {
        playerState = PlayerState.stopped;
        duration = new Duration(seconds: 0);
        position = new Duration(seconds: 0);
      });
    });
  }

  Future play() async {
    subTitle = await _loadSubtitle();
    await audioPlayer.play(await _loadMedia());
    setState(() => playerState = PlayerState.playing);
  }

  Future pause() async {
    await audioPlayer.pause();
    setState(() => playerState = PlayerState.paused);
  }

  Future stop() async {
    await audioPlayer.stop();
    setState(() {
      playerState = PlayerState.stopped;
      position = new Duration();
    });
  }

  Future mute(bool muted) async {
    await audioPlayer.setVolume(muted ? 0 : 0.3);
    setState(() {
      isMuted = muted;
    });
  }

  void onComplete() {
    setState(() => playerState = PlayerState.stopped);
  }

  Future<String> _loadMedia() async {
    Directory directory = await getApplicationDocumentsDirectory();
    String path = directory.path + '/_adventuresherlockholmes_01_doyle.mp3';

    ByteData data =
        await rootBundle.load("assets/adventuresherlockholmes_01_doyle.mp3");
    List<int> bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await File(path).writeAsBytes(bytes);

    return path;
  }

  Future<List<Subtitle>> _loadSubtitle() async {
    Directory directory = await getApplicationDocumentsDirectory();
    String path = directory.path + '/_adventuresherlockholmes_01_doyle.srt';

    ByteData data =
        await rootBundle.load("assets/adventuresherlockholmes_01_doyle.srt");
    List<int> bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    var file = await File(path).writeAsBytes(bytes);

    List<Subtitle> subtitle = List<Subtitle>();

    List<String> rfile = await file.readAsLinesSync();
    var i = 0;
    for (var item in rfile) {
      if (item.isEmpty) {
        subtitle.add(Subtitle(
            rfile[i + 1].toString(),
            DateFormat('HH:mm:ss.SSS')
                .parse(rfile[i + 2].toString().split('-->')[0].trim()),
            DateFormat('HH:mm:ss.SSS')
                .parse(rfile[i + 2].toString().split('-->')[1].trim()),
            rfile[i + 3]));
      }
      i++;
    }

    return subtitle;
  }

  @override
  Widget build(BuildContext context) {
    return new Center(
      child: new Material(
        elevation: 2.0,
        color: Colors.grey[200],
        child: new Center(
          child: new Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              mainAxisSize: MainAxisSize.min,
              children: [
                new Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: richText,
                ),
                //Text(
                //  currentCaption,
                //  style: TextStyle(
                //      color: Colors.deepPurpleAccent, fontSize: 24.0),
                //)),
                new Material(child: _buildPlayer()),
              ]),
        ),
      ),
    );
  }

  Widget _buildPlayer() => new Container(
      padding: new EdgeInsets.all(16.0),
      child: new Column(mainAxisSize: MainAxisSize.min, children: [
        new Row(mainAxisSize: MainAxisSize.min, children: [
          new IconButton(
              onPressed: isPlaying ? null : () => play(),
              iconSize: 64.0,
              icon: new Icon(Icons.play_arrow),
              color: Colors.cyan),
          new IconButton(
              onPressed: isPlaying ? () => pause() : null,
              iconSize: 64.0,
              icon: new Icon(Icons.pause),
              color: Colors.cyan),
          new IconButton(
              onPressed: isPlaying || isPaused ? () => stop() : null,
              iconSize: 64.0,
              icon: new Icon(Icons.stop),
              color: Colors.cyan),
        ]),
        duration == null
            ? new Container()
            : new Slider(
                value: position?.inMilliseconds?.toDouble() ?? 0.0,
                onChanged: (double value) => audioPlayer
                    .seek(Duration(milliseconds: (value / 1200).round())),
                min: 0.0,
                max: duration.inMilliseconds.toDouble()),
        new Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            new IconButton(
                onPressed: () => mute(true),
                icon: new Icon(Icons.headset_off),
                color: Colors.cyan),
            new IconButton(
                onPressed: () => mute(false),
                icon: new Icon(Icons.headset),
                color: Colors.cyan),
          ],
        ),
        new Row(mainAxisSize: MainAxisSize.min, children: [
          new Padding(
              padding: new EdgeInsets.all(12.0),
              child: new Stack(children: [
                new CircularProgressIndicator(
                    value: 1.0,
                    valueColor: new AlwaysStoppedAnimation(Colors.grey[300])),
                new CircularProgressIndicator(
                  value: position != null && position.inMilliseconds > 0
                      ? (position?.inMilliseconds?.toDouble() ?? 0.0) /
                          (duration?.inMilliseconds?.toDouble() ?? 0.0)
                      : 0.0,
                  valueColor: new AlwaysStoppedAnimation(Colors.cyan),
                  backgroundColor: Colors.yellow,
                ),
              ])),
          new Text(_currentPosition(), style: new TextStyle(fontSize: 24.0))
        ])
      ]));
}
