import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:home_widget/home_widget.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Potato Weather',

      themeMode: ThemeMode.system,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),

      home: const HomeTabs(),
    );
  }
}

class HomeTabs extends StatefulWidget {
  const HomeTabs({super.key});

  @override
  State<HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<HomeTabs> {
  Map<String, dynamic>? forecast;
  Map<String, dynamic>? currentWeather;
  List<dynamic>? alerts;
  bool loading = false;

  final AudioPlayer audioPlayer = AudioPlayer();
  PlayerState audioState = PlayerState.stopped;

  double lat = 42.3314;
  double lon = -83.0458;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  void _initLocation() async {
    final loc = await _getLocationFromIPWhois();
    if (loc != null) {
      lat = loc['lat']!;
      lon = loc['lon']!;
    }
    fetchAllForLocation(lat, lon);
  }

  // ⭐ FIXED — using ipwho.is (ipwhois)
  Future<Map<String, double>?> _getLocationFromIPWhois() async {
    try {
      final response = await http.get(Uri.parse('https://ipwho.is/'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final la = (data['latitude'] as num?)?.toDouble();
          final lo = (data['longitude'] as num?)?.toDouble();
          if (la != null && lo != null) return {'lat': la, 'lon': lo};
        }
      }
    } catch (e) {
      debugPrint('IPWhois error: $e');
    }
    return null;
  }

  Future<void> fetchAllForLocation(double lat, double lon) async {
    setState(() => loading = true);

    final headers = {
      'User-Agent': 'PotatoWeatherApp (example@example.com)',
      'Accept': 'application/geo+json, application/json'
    };

    try {
      final pointsUrl = Uri.parse('https://api.weather.gov/points/$lat,$lon');
      final pResp = await http.get(pointsUrl, headers: headers);
      if (pResp.statusCode != 200) throw Exception('Points failed');

      final props = json.decode(pResp.body)['properties'];
      final forecastUrl = props['forecast'];
      final alertsUrl =
          'https://api.weather.gov/alerts/active?point=$lat,$lon';

      final fResp = await http.get(Uri.parse(forecastUrl), headers: headers);
      if (fResp.statusCode == 200) forecast = json.decode(fResp.body);

      currentWeather = forecast?['properties']?['periods']?[0];

      final aResp = await http.get(Uri.parse(alertsUrl), headers: headers);
      if (aResp.statusCode == 200) alerts = json.decode(aResp.body)['features'];

      try {
        final tempText =
            currentWeather?['temperature']?.toString() ?? 'No data';
        await HomeWidget.saveWidgetData<String>('temp', tempText);
        await HomeWidget.updateWidget(
          name: 'PotatoWeatherWidgetProvider',
          iOSName: '',
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('Fetch error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  Widget currentTab() {
    if (currentWeather == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: ListTile(
          title: Text(
            '${currentWeather!['name'] ?? 'Now'}: '
            '${currentWeather!['temperature'] ?? '?'} '
            '${currentWeather!['temperatureUnit'] ?? ''}',
          ),
          subtitle: Text(currentWeather!['shortForecast'] ?? ''),
        ),
      ),
    );
  }

  Widget forecastTab() {
    final periods =
        (forecast?['properties']?['periods'] ?? []) as List<dynamic>;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (loading) const CircularProgressIndicator(),
          if (!loading && periods.isEmpty)
            const Text('No forecast available'),
          if (periods.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: periods.length,
                itemBuilder: (_, i) {
                  final p = periods[i];
                  return ListTile(
                    title: Text(
                        '${p['name']} - ${p['temperature']} ${p['temperatureUnit']}'),
                    subtitle: Text(p['shortForecast'] ?? ''),
                  );
                },
              ),
            )
        ],
      ),
    );
  }

  // ⭐ PATCHED radarTab
  Widget radarTab() => RadarTab(lat: lat, lon: lon);

  Widget alertsTab() {
    if (alerts == null) return const Center(child: Text('No alerts loaded'));
    if (!loading && alerts!.isEmpty) {
      return const Center(child: Text('No active alerts'));
    }

    return ListView.builder(
      itemCount: alerts!.length,
      itemBuilder: (_, i) {
        final a = alerts![i]['properties'] ?? {};
        final headline = a['headline'] ?? a['event'] ?? 'Alert';

        return Card(
          child: ListTile(
            title: Text(headline),
            subtitle: Text(a['description'] ?? ''),
            onTap: () {
              final uri = a['uri'] as String?;
              if (uri != null) launchUrl(Uri.parse(uri));
            },
          ),
        );
      },
    );
  }

  // ⭐ Radio Tab — GREYED OUT
  Widget radioTab() {
    return const Center(
      child: Text(
        "This Feature is Temporarily Unavailable",
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget snowDayTab() {
    return Center(
      child: ElevatedButton(
        onPressed: () => launchUrl(Uri.parse('https://snowdaycalculator.com'),
            mode: LaunchMode.externalApplication),
        child: const Text('Open Snow Day Calculator'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const Tab(icon: Icon(Icons.thermostat), text: 'Current'),
      const Tab(icon: Icon(Icons.cloud), text: 'Forecast'),
      const Tab(icon: Icon(Icons.radar), text: 'Radar'),
      const Tab(icon: Icon(Icons.warning), text: 'Alerts'),
      const Tab(icon: Icon(Icons.radio), text: 'Radio'),
      const Tab(icon: Icon(Icons.calendar_today), text: 'Snow Day'),
    ];

    final tabViews = [
      currentTab(),
      forecastTab(),
      radarTab(),
      alertsTab(),
      radioTab(),
      snowDayTab(),
    ];

  return DefaultTabController(
    length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Image.asset(
                'assets/images/logo.png',
                height: 32,
                width: 32,
              ),
              const SizedBox(width: 8),
              const Text('Potato Weather'),
            ],
          ),
          bottom: TabBar(
            tabs: tabs,
            isScrollable: true,
          ),
        ),
        body: TabBarView(
          children: tabViews,
        ),
      ),
    );
  }
}

// ⭐ NEW StatefulWidget for radar tab
class RadarTab extends StatefulWidget {
  final double lat;
  final double lon;
  const RadarTab({super.key, required this.lat, required this.lon});

  @override
  State<RadarTab> createState() => _RadarTabState();
}

class _RadarTabState extends State<RadarTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // keeps the map alive when switching tabs

  @override
  Widget build(BuildContext context) {
    super.build(context); // required with AutomaticKeepAliveClientMixin
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(widget.lat, widget.lon),
            initialZoom: 6,
            minZoom: 3,
            maxZoom: 12,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            ),
            TileLayer(
              urlTemplate:
                  'https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.potatoweather.app',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(widget.lat, widget.lon),
                  width: 80,
                  height: 80,
                  child: const Icon(Icons.location_pin,
                      color: Colors.red, size: 36),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
