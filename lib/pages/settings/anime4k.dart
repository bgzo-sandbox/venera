part of 'settings_page.dart';

class Anime4KSettings extends StatefulWidget {
  const Anime4KSettings({super.key});

  @override
  State<Anime4KSettings> createState() => _Anime4KSettingsState();
}

class _Anime4KSettingsState extends State<Anime4KSettings> {
  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text('超分')),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('功能说明', style: ts.s16),
              const SizedBox(height: 6),
              Text(
                '当前超分算法为 Anime4K，更适合线稿、漫画和彩漫边缘增强。对原图本身就很糊、压缩严重的图片，提升通常有限。',
                style: ts.s12.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ).toSliver(),
        _SwitchSetting(
          title: '启用',
          settingKey: 'enableAnime4K',
          subtitle: '开启后，阅读器会在后台进行超分处理，当前使用的算法是 Anime4K。',
          onChanged: () {
            setState(() {});
          },
        ).toSliver(),
        if (appdata.settings['enableAnime4K'] == true)
          _SwitchSetting(
            title: '网络图片',
            settingKey: 'enableAnime4KForNetwork',
            subtitle: '在线阅读时也执行超分处理，当前算法为 Anime4K。会增加加载后的处理时间和内存占用。',
            onChanged: () {
              setState(() {});
            },
          ).toSliver(),
        if (appdata.settings['enableAnime4K'] == true)
          _SliderSetting(
            title: '放大倍率',
            settingsIndex: 'anime4KScaleFactor',
            interval: 0.5,
            min: 1.0,
            max: 4.0,
            subtitle: '推荐 1.5 - 2.0。倍率越高，边缘更锐，但耗时和内存占用都会明显上升。',
            onChanged: () {
              setState(() {});
            },
          ).toSliver(),
        if (appdata.settings['enableAnime4K'] == true)
          _SliderSetting(
            title: '线条细化强度',
            settingsIndex: 'anime4KPushStrength',
            interval: 0.01,
            min: 0.0,
            max: 1.0,
            subtitle: '推荐 0.2 - 0.4。数值越大，黑线会更锐利，但过高可能出现发硬、锯齿或细节丢失。',
            onChanged: () {
              setState(() {});
            },
          ).toSliver(),
        if (appdata.settings['enableAnime4K'] == true)
          _SliderSetting(
            title: '边缘精炼强度',
            settingsIndex: 'anime4KPushGradStrength',
            interval: 0.01,
            min: 0.0,
            max: 2.0,
            subtitle: '推荐 0.8 - 1.2。主要增强边缘过渡，过高时可能让噪点和压缩痕迹更明显。',
            onChanged: () {
              setState(() {});
            },
          ).toSliver(),
        if (appdata.settings['enableAnime4K'] == true)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: context.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('调参建议', style: ts.s14),
                const SizedBox(height: 4),
                Text(
                  '先把放大倍率设为 2.0，再微调“线条细化强度”和“边缘精炼强度”。当前算法 Anime4K 更偏向边缘增强，不能把低质量压缩图直接恢复成高清原图。',
                  style: ts.s12.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ).toSliver(),
      ],
    );
  }
}
