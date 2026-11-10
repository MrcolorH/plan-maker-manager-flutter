import assert from 'node:assert';
import { parseMealText } from '../src/utils/textParser.js';

// Case 1: 真实的跨行属性块 + "总计：" (今日中午导致 bug 的案例)
const textMultiLine = `这道番茄鸡蛋荞麦焖面的搭配很健康呀，营养也很均衡。萌萌给主人把各项食材的数据理出来啦：

1. 番茄（约2个中等大小）
预估克数：300g | 预估热量：45 kcal | 蛋白质 2.7g / 脂肪 0.6g / 碳水 9.9g

2. 鸡蛋（2个）
预估克数：100g | 预估热量：144 kcal | 蛋白质 12.6g / 脂肪 9.8g / 碳水 1.5g

3. 烹调油
预估克数：5g | 预估热量：45 kcal | 蛋白质 0.0g / 脂肪 5.0g / 碳水 0.0g

4. 荞麦面（干重）
预估克数：60g | 预估热量：204 kcal | 蛋白质 6.8g / 脂肪 1.4g / 碳水 42.0g

总计：
总热量：约 438 kcal
蛋白质：22.1g
脂肪：16.8g
碳水化合物：53.4g

营养小结：
这顿饭碳水、蛋白质和优质蔬菜都有兼顾到，5g控油做得非常棒，热量控制得很理想。如果番茄酸甜多汁，少放点盐会更利于水分代谢呢。

👉 请核对以上识别是否有误？如果您知道某道菜或整盒饭菜的实际称重（克数），也可以告诉我，我将按真实重量为您重新精细计算！`;

// Case 2: 单行管道符 + "【总计与营养小结】" (今日上午成功的案例)
const textSingleLine = `盘子里的菜品萌萌看清楚啦，按份量帮主人做好了营养估算：

1. 白米饭：预估 180g | 预估热量 210kcal | 蛋白质 4.7g / 脂肪 0.5g / 碳水 46.6g
2. 水煮/白灼瘦肉片：预估 70g | 预估热量 100kcal | 蛋白质 14.2g / 脂肪 4.5g / 碳水 0.7g
3. 青椒炒肉丝/鸡胗：预估 60g | 预估热量 95kcal | 蛋白质 10.5g / 脂肪 5.2g / 碳水 1.5g
4. 炒蒜苔/长豆角：预估 70g | 预估热量 55kcal | 蛋白质 1.5g / 脂肪 3.0g / 碳水 5.5g
5. 清炒西兰花：预估 60g | 预估热量 35kcal | 蛋白质 1.6g / 脂肪 1.8g / 碳水 3.1g
6. 凉拌豆腐丝：预估 20g | 预估热量 30kcal | 蛋白质 2.8g / 脂肪 1.6g / 碳水 1.0g
7. 红烧肉/卤肉小块：预估 25g | 预估热量 80kcal | 蛋白质 3.5g / 脂肪 7.2g / 碳水 0.5g

【总计与营养小结】
总热量预估：约 605 kcal
三大宏量：蛋白质 38.8g / 脂肪 23.8g / 碳水 58.9g`;

// Case 3: 逗号分隔单行 (历史格式)
const textCommaLine = `经过分析，本餐菜品：米饭 150g (175 kcal), 煎鸡胸肉 150g (300 kcal), 炒绿豆芽 100g (50 kcal)。预估【总热量】: 525 kcal，三大营养素配比均衡。`;

console.log('--- 测试 Case 1 (跨行块模式) ---');
const res1 = parseMealText(textMultiLine);
console.log('Result 1:', JSON.stringify(res1, null, 2));

console.log('--- 测试 Case 2 (单行管道符) ---');
const res2 = parseMealText(textSingleLine);
console.log('Result 2:', JSON.stringify(res2, null, 2));

console.log('--- 测试 Case 3 (逗号分隔单行) ---');
const res3 = parseMealText(textCommaLine);
console.log('Result 3:', JSON.stringify(res3, null, 2));
