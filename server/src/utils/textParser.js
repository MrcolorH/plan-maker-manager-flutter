/**
 * 知轻多端协同文本解析器 (与知轻 App AiService 规则完全统一)
 * 能够从 AI 助手、聊天记录、外卖清单或口语输入的多行/长文本中，
 * 完整提取所有食物子项 (items: name, portion, calories)、总热量、餐次 (slot)、三大营养素及概述标题。
 */

function cleanFoodBreakdownName(name) {
  if (!name) return '';
  let s = name.trim();
  // 剔除前缀如 "本餐菜品："、"菜品："、"餐品："、"包含："、"含有："、序号、项目符号
  s = s.replace(/^(?:(?:本餐|今日|本次)?(?:菜品|餐品|食物|包含|包括|含有|有)[：:]\s*)/i, '');
  s = s.replace(/^(?:\d+[\.、\s]+|[-*•]\s*|[\u2460-\u2473]\s*)/, '').trim();
  s = s.replace(/^[:：\s]+|[:：\s]+$/g, '');
  return s;
}

const INVALID_KEYWORDS = new Set([
  '合计', '总计', '共计', '小计', '整餐', '整餐总重', '菜品总重', '米饭重量', '食物总重', '总重量',
  '预估克数', '预估重量', '预估份量', '预估热量', '预估总热量', '总热量预估', '标称热量', '实际热量', '总热量',
  '蛋白质', '脂肪', '碳水', '碳水化合物', '钠', '膳食纤维', '热量', '卡路里',
  '蛋白质总量', '脂肪总量', '碳水总量', '缩放系数', '等比例缩放', '修正后总计', '营养小结',
  '如无误', '请核对', '确认', '打卡', '核算', '三大营养素', '三大宏量', '营养分析', '减脂建议', '建议',
  '小结与建议'
]);

function isValidFoodBreakdownName(name) {
  if (!name) return false;
  const trimmed = name.trim();
  if (!trimmed) return false;
  // 排除纯数字、纯符号、算式
  if (/^[\d\s\.\+\-\*\/=＝≈~:：,，;；()（）\[\]【】%％#№|｜]+$/.test(trimmed)) return false;
  // 排除单纯的数字序号，如 "1." 或 "1"
  if (/^\d+[\.、]?$/.test(trimmed)) return false;

  const cleanName = trimmed.replace(/[:：\s【】\[\]（）\(\)|｜]/g, '');
  if (INVALID_KEYWORDS.has(cleanName)) return false;
  for (const kw of INVALID_KEYWORDS) {
    if (cleanName === kw || cleanName.startsWith(kw) || cleanName.endsWith(kw)) {
      return false;
    }
  }
  return true;
}

function parseParen(inner) {
  if (!inner) return null;
  const clean = inner.trim();
  // 1. 包含逗号的格式: "1碗, 550kcal" 或 "150g, 300 kcal"
  if (clean.includes(',') || clean.includes('，')) {
    const parts = clean.split(/[,，]/);
    const p1 = parts[0].trim();
    const p2 = parts[1].trim();
    const c2 = p2.match(/(-?\d+)\s*(?:kcal|大卡|卡路里|千卡)/i);
    if (c2) {
      return { portion: p1, calories: parseInt(c2[1], 10) };
    }
    const c1 = p1.match(/(-?\d+)\s*(?:kcal|大卡|卡路里|千卡)/i);
    if (c1) {
      return { portion: p2, calories: parseInt(c1[1], 10) };
    }
  }
  // 2. 纯热量: 必须明确带有热量单位，绝不能将任意数字（如 "2个"）误认作热量
  const mCal = clean.match(/(-?\d+)\s*(?:kcal|大卡|卡路里|千卡)/i);
  if (mCal) {
    return { portion: '', calories: parseInt(mCal[1], 10) };
  }
  return null;
}

export function parseMealText(text) {
  if (!text || !text.trim()) {
    return {
      slot: 'lunch',
      content: '午餐打卡',
      calories: 500,
      protein: 0,
      carbs: 0,
      fat: 0,
      items: []
    };
  }

  const clean = text.trim();

  // 1. 优先提取总热量 (全局匹配)
  let calories = 0;
  const totalRegex = /(?:(?:总热量预估|预估总热量|整餐总热量|总热量合计|总热量|总能量|合计约|总计约|预估【总热量】|【总热量】|合计|总计|共计|共约|小计)\s*】?)\s*[:：约约为]*\s*(-?\d+)\s*(?:kcal|大卡|卡路里|千卡)?/i;
  const totalMatch = clean.match(totalRegex);
  if (totalMatch && totalMatch[1]) {
    calories = parseInt(totalMatch[1], 10);
  }

  // 截取总结段与清单段 (兼容带与不带【】方括号的各类总计与小结格式)
  let foodListSection = clean;
  let summarySection = '';
  const summarySplit = clean.search(/(?:(?:【?\s*(?:总计|营养小结|营养总计|营养数据|营养成分|营养分析|总结|小结|整餐统计|三大营养素|三大宏量|宏量数据)(?:与[^\n:：]+)?\s*】?[:：]?)|小结与建议|这一餐的搭配|👉)/i);
  if (summarySplit !== -1) {
    foodListSection = clean.substring(0, summarySplit).trim();
    summarySection = clean.substring(summarySplit).trim();
  }

  // 2. 提取三大营养素 (优先从总结段提取，若未找到则回退到全文匹配)
  let protein = 0;
  let carbs = 0;
  let fat = 0;

  function extractMacrosFromText(sourceText) {
    let p = 0, c = 0, f = 0;
    if (!sourceText) return { p, c, f };
    const pMatch = sourceText.match(/(?:蛋白质|蛋白|P)\s*[:：约约为\s]*(\d+(?:\.\d+)?)\s*g?/i);
    if (pMatch) p = Math.round(parseFloat(pMatch[1]));
    const cMatch = sourceText.match(/(?:碳水化合物|碳水|C)\s*[:：约约为\s]*(\d+(?:\.\d+)?)\s*g?/i);
    if (cMatch) c = Math.round(parseFloat(cMatch[1]));
    const fMatch = sourceText.match(/(?:脂肪|油脂|F)\s*[:：约约为\s]*(\d+(?:\.\d+)?)\s*g?/i);
    if (fMatch) f = Math.round(parseFloat(fMatch[1]));
    return { p, c, f };
  }

  const sumMacros = extractMacrosFromText(summarySection);
  protein = sumMacros.p;
  carbs = sumMacros.c;
  fat = sumMacros.f;

  if (protein === 0 || carbs === 0 || fat === 0) {
    const fullMacros = extractMacrosFromText(clean);
    if (protein === 0) protein = fullMacros.p;
    if (carbs === 0) carbs = fullMacros.c;
    if (fat === 0) fat = fullMacros.f;
  }

  const items = [];
  let itemProteinSum = 0;
  let itemCarbsSum = 0;
  let itemFatSum = 0;

  // 模式 1 (优先)：结构化多行序号条目块 (Block Mode)
  // 当文本中存在明确序号 (如 1. / 2. 或 (1) / (2)) 时，按条目块完整提取食物名、克数、热量与宏量
  const blockSplits = [];
  const blockRegex = /(?:^|\n)\s*(?:\d+[\.、]|\([0-9]+\)|（[0-9]+）)\s*/g;
  let bMatch;
  while ((bMatch = blockRegex.exec(foodListSection)) !== null) {
    blockSplits.push({ start: bMatch.index + bMatch[0].length, index: bMatch.index });
  }

  if (blockSplits.length > 0) {
    for (let i = 0; i < blockSplits.length; i++) {
      const start = blockSplits[i].start;
      const end = (i + 1 < blockSplits.length) ? blockSplits[i + 1].index : foodListSection.length;
      const block = foodListSection.substring(start, end).trim();
      const bLines = block.split(/[\r\n]+/)
        .map(e => e.trim())
        .filter(e => {
          if (!e) return false;
          if (/(?:合计|总计|共计|小计|总热量|整餐总重|预估总热量|总热量预估|三大宏量|营养小结)/i.test(e)) return false;
          return true;
        });
      if (bLines.length === 0) continue;

      const rawFirstLine = bLines[0];

      // 1.1 若第一行即为单行管道符格式: "白米饭：预估 180g | 预估热量 210kcal | 蛋白质 ..."
      if (rawFirstLine.includes('|') || rawFirstLine.includes('｜')) {
        const parts = rawFirstLine.split(/[|｜]/);
        const namePart = parts[0].trim();
        let name = '';
        let portion = '';
        if (namePart.includes('：') || namePart.includes(':')) {
          const np = namePart.split(/[:：]/);
          name = cleanFoodBreakdownName(np[0]);
          portion = np.slice(1).join(':').replace(/^(?:预估|约)?\s*/, '').trim();
        } else {
          name = cleanFoodBreakdownName(namePart);
        }

        let cal = 0;
        for (let pIdx = 1; pIdx < parts.length; pIdx++) {
          const part = parts[pIdx].trim();
          const mCal = part.match(/(?:预估热量|热量|能量)\s*[:：约约为\s]*(-?\d+)\s*(?:kcal|大卡|卡路里|千卡)?|(-?\d+)\s*(?:kcal|大卡|卡路里|千卡)/i);
          if (mCal) {
            const val = parseInt(mCal[1] || mCal[2], 10);
            if (val > 0) cal = val;
          }
          if (!portion) {
            const mPort = part.match(/(?:预估克数|克数|重量|份量)\s*[:：约约为\s]*([\d\.\/]+[^\s\|｜]+)/i);
            if (mPort) portion = mPort[1].trim();
          }
        }

        // 提取该项可能附带的微量/宏量
        const mSub = extractMacrosFromText(block);
        itemProteinSum += mSub.p;
        itemCarbsSum += mSub.c;
        itemFatSum += mSub.f;

        if (cal > 0 && isValidFoodBreakdownName(name)) {
          items.push({ name, portion, calories: cal });
          continue;
        }
      }

      // 1.2 跨行属性块格式: 第一行是菜名 (如 "番茄（约2个中等大小）")，下一行是属性管道符或多行键值
      let rawName = rawFirstLine.replace(/[:：]$/, '').trim();
      let inlinePortion = '';
      // 检查菜名是否自带括号份量，如 "番茄（约2个中等大小）" 或 "鸡蛋（2个）"
      const mNameParen = rawName.match(/^([^\(（]+?)[\(（]([^\)）]+)[\)）]\s*$/);
      if (mNameParen) {
        rawName = mNameParen[1].trim();
        inlinePortion = mNameParen[2].trim();
      }

      const name = cleanFoodBreakdownName(rawName);
      if (!isValidFoodBreakdownName(name)) continue;

      // 在该块中提取热量
      const calMatch = block.match(/(?:预估热量|热量|能量|卡路里)[:：约约为\s]*(-?\d+)\s*(?:kcal|大卡|千卡)?/i);
      let cal = calMatch ? parseInt(calMatch[1], 10) : 0;

      // 在该块中提取重量/份量 (严格在管道符或换行处截止，避免整行污染)
      const portionMatch = block.match(/(?:预估克数|克数|重量|份量)[:：约约为\s]*([^\n\r|｜]+)/i);
      let portion = portionMatch ? portionMatch[1].trim() : (inlinePortion || '');

      if (cal === 0) {
        const anyCal = block.match(/(-?\d+)\s*(?:kcal|大卡|卡路里|千卡)/i);
        if (anyCal) cal = parseInt(anyCal[1], 10);
      }
      if (!portion) {
        const anyPortion = block.match(/([\d\.\/]+(?:g|克|ml|毫升|个|份|碗|盘|勺|片|条|支|根|杯)(?:\([^\)]+\)|（[^）]+）)?)/i);
        if (anyPortion) portion = anyPortion[1].trim();
      }

      const mSub = extractMacrosFromText(block);
      itemProteinSum += mSub.p;
      itemCarbsSum += mSub.c;
      itemFatSum += mSub.f;

      if (cal !== 0 || portion) {
        items.push({ name, portion, calories: cal });
      }
    }
  }

  // 模式 2 (回退)：逐行单行格式 (Line Mode)
  if (items.length === 0) {
    const lines = foodListSection.split(/[\r\n]+/);
    for (const rawLine of lines) {
      const l = rawLine.trim();
      if (!l) continue;
      if (/^(?:盘子里|这餐搭配|为您估算|经过分析|收到|根据|👉|💡|注意|建议|总结|小结|营养|三大|如无误|请核对)/i.test(l)) continue;
      if (/(?:合计|总计|共计|小计|总热量|预估总热量|总热量预估|整餐总重|预估【总热量】|【总热量】)/i.test(l)) continue;

      // 检查管道符格式: "1. 白米饭：预估 180g | 预估热量 210kcal | 蛋白质 ..."
      if (l.includes('|') || l.includes('｜')) {
        const parts = l.split(/[|｜]/);
        const namePart = parts[0].trim();
        let name = '';
        let portion = '';
        if (namePart.includes('：') || namePart.includes(':')) {
          const np = namePart.split(/[:：]/);
          name = cleanFoodBreakdownName(np[0]);
          portion = np.slice(1).join(':').replace(/^(?:预估|约)?\s*/, '').trim();
        } else {
          const mP = namePart.match(/^(?:(?:\d+[\.、\s]+|[-*•]\s*|[\u2460-\u2473]\s*))?([^\d\(\（:：,，\-\+\*\/]+?)\s*([\d\.\/]+(?:g|克|ml|毫升|个|份|碗|盘|勺|片|条|支|根|杯)?(?:\([^\)]+\)|（[^）]+）)?)$/i);
          if (mP) {
            name = cleanFoodBreakdownName(mP[1]);
            portion = (mP[2] || '').trim();
          } else {
            name = cleanFoodBreakdownName(namePart);
          }
        }

        let cal = 0;
        for (let pIdx = 1; pIdx < parts.length; pIdx++) {
          const part = parts[pIdx].trim();
          const mCal = part.match(/(?:预估热量|热量|能量)\s*[:：约约为\s]*(-?\d+)\s*(?:kcal|大卡|卡路里|千卡)?|(-?\d+)\s*(?:kcal|大卡|卡路里|千卡)/i);
          if (mCal) {
            const val = parseInt(mCal[1] || mCal[2], 10);
            if (val > 0) cal = val;
          }
          if (!portion) {
            const mPort = part.match(/(?:预估克数|克数|重量|份量)\s*[:：约约为\s]*([\d\.\/]+[^\s\|｜]+)/i);
            if (mPort) portion = mPort[1].trim();
          }
        }

        if (cal > 0 && isValidFoodBreakdownName(name)) {
          items.push({ name, portion, calories: cal });
          continue;
        }
      }

      // 格式 A1: 带有括号的行，例如: "- 原味全脂纯牛奶 250ml (160 kcal)" 或 "1. 煎鸡胸肉 (150g, 300 kcal)"
      const mLineParen = l.match(/^(?:(?:\d+[\.、\s]+|[-*•]\s*|[\u2460-\u2473]\s*))?([^\(（]+?)(?:\s+([\d\.\/]+[^\d\s\(\)（）]*))?\s*[\(（]([^\)）]+)[\)）]\s*$/);
      if (mLineParen) {
        const name = cleanFoodBreakdownName(mLineParen[1]);
        const portionOutside = (mLineParen[2] || '').trim();
        const parenRes = parseParen(mLineParen[3]);
        if (parenRes && isValidFoodBreakdownName(name)) {
          items.push({
            name,
            portion: portionOutside || parenRes.portion || '',
            calories: parenRes.calories
          });
          continue;
        }
      }

      // 格式 A2: 冒号分隔带份量与热量，例如: "1. 白米饭 200g：约 232 kcal"
      const mItem = l.match(/^(?:(?:\d+[\.、\s]+|[-*•]\s*|[\u2460-\u2473]\s*))?([^\d\(\（:：,，\-\+\*\/]+?)\s*([\d\.\/]+(?:g|克|ml|毫升|个|份|碗|盘|勺|片|条|支|根|杯)?(?:\([^\)]+\)|（[^）]+）)?)\s*[:：≈=约\s]+(-?\d+)\s*(?:kcal|大卡|卡路里|千卡)?$/i);
      if (mItem) {
        const name = cleanFoodBreakdownName(mItem[1]);
        const portion = (mItem[2] || '').trim();
        const cal = parseInt(mItem[3], 10) || 0;
        if (isValidFoodBreakdownName(name)) {
          items.push({ name, portion, calories: cal });
          continue;
        }
      }

      // 格式 A3: 纯冒号分隔: "煎鸡蛋: 90大卡"
      const mSimple = l.match(/^(?:(?:\d+[\.、\s]+|[-*•]\s*|[\u2460-\u2473]\s*))?([^\d\(\（:：,，\-\+\*\/]+?)\s*[:：≈=约\s]+(-?\d+)\s*(?:kcal|大卡|卡路里|千卡)?$/i);
      if (mSimple) {
        const name = cleanFoodBreakdownName(mSimple[1]);
        const cal = parseInt(mSimple[2], 10) || 0;
        if (isValidFoodBreakdownName(name)) {
          items.push({ name, portion: '', calories: cal });
          continue;
        }
      }
    }
  }

  // 模式 3 (回退)：段落逗号/波浪号切分 (Inline Mode)
  if (items.length <= 1) {
    const inlineItems = [];
    const inlineContent = foodListSection.replace(/(?:[，,；;\s]|\b)?[\(（]?\s*(?:\d+\s*[\+＋]\s*)+\d+\s*(?:[=＝]\s*\d+)?\s*[\)）]?/gi, '').trim();
    
    const segments = [];
    let depth = 0;
    let current = '';
    for (let i = 0; i < inlineContent.length; i++) {
      const char = inlineContent[i];
      if (char === '(' || char === '（') {
        depth++;
        current += char;
      } else if (char === ')' || char === '）') {
        if (depth > 0) depth--;
        current += char;
      } else if (depth === 0 && (char === '，' || char === ',' || char === ';' || char === '；' || char === '+' || char === '\n' || char === '\r' || char === '。')) {
        const s = current.trim();
        if (s) segments.push(s);
        current = '';
      } else {
        current += char;
      }
    }
    const rem = current.trim();
    if (rem) segments.push(rem);

    for (const rawSeg of segments) {
      let seg = rawSeg.trim();
      if (!seg) continue;
      if (/^[\d\s\.\+\-\*\/=＝≈~:：,，;；()（）\[\]【】%％#№]+$/.test(seg)) continue;
      if (/(?:合计|总计|共计|小计|总热量|整餐总重|菜品总重|米饭重量|修正后总计|营养小结|预估总热量|总热量预估|三大宏量|蛋白质总量|脂肪总量|碳水总量|三大营养素)\b/i.test(seg)) continue;

      seg = cleanFoodBreakdownName(seg);

      const mParen = seg.match(/^([^\(（]+?)(?:\s+([\d\.\/]+[^\d\s\(\)（）]*))?\s*[\(（]([^\)）]+)[\)）]\s*$/);
      if (mParen) {
        const name = cleanFoodBreakdownName(mParen[1]);
        const portionOutside = (mParen[2] || '').trim();
        const parenRes = parseParen(mParen[3]);
        if (parenRes && isValidFoodBreakdownName(name)) {
          inlineItems.push({
            name,
            portion: portionOutside || parenRes.portion || '',
            calories: parenRes.calories
          });
          continue;
        }
      }

      const sepMatch = seg.match(/(.+?)\s*([≈=：:])\s*(-?\d+)\s*(?:kcal|大卡)?/i);
      if (sepMatch) {
        const left = sepMatch[1].trim();
        const cal = parseInt(sepMatch[3], 10) || 0;
        const pMatch = left.match(/([\d\.\/]+[^\d\s\(\)（）]+(?:\([^\)]+\)|（[^）]+）)?)\s*$/);
        if (pMatch) {
          const portion = pMatch[1].trim();
          const rawName = left.substring(0, pMatch.index).trim();
          const name = cleanFoodBreakdownName(rawName || left);
          if (isValidFoodBreakdownName(name)) {
            inlineItems.push({ name, portion, calories: cal });
            continue;
          }
        } else {
          const name = cleanFoodBreakdownName(left);
          if (isValidFoodBreakdownName(name)) {
            inlineItems.push({ name, portion: '', calories: cal });
            continue;
          }
        }
      }

      const endCal = seg.match(/^(.+?)\s+(-?\d+)\s*(?:kcal|大卡)?\s*$/i);
      if (endCal) {
        const left = endCal[1].trim();
        const cal = parseInt(endCal[2], 10) || 0;
        const name = cleanFoodBreakdownName(left);
        if (isValidFoodBreakdownName(name)) {
          inlineItems.push({ name, portion: '', calories: cal });
        }
      }
    }

    if (inlineItems.length > items.length) {
      items.length = 0;
      items.push(...inlineItems);
    }
  }

  // 3. 校准三大宏量 (若宏量依然为 0，尝试使用子项累计作为兜底)
  if (protein === 0 && itemProteinSum > 0) protein = itemProteinSum;
  if (carbs === 0 && itemCarbsSum > 0) carbs = itemCarbsSum;
  if (fat === 0 && itemFatSum > 0) fat = itemFatSum;

  // 4. 校准总热量
  if (calories === 0) {
    if (items.length > 0) {
      calories = items.reduce((sum, it) => sum + (it.calories || 0), 0);
    } else {
      const anyCal = clean.match(/(\d{2,4})\s*(?:kcal|大卡|卡路里|千卡)/i);
      calories = anyCal ? parseInt(anyCal[1], 10) : 500;
    }
  }

  // 5. 智能识别餐次 slot
  const d = new Date();
  const hour = d.getHours();
  let slot = 'lunch';
  if (clean.includes('早餐') || clean.includes('早饭') || (!clean.includes('午') && !clean.includes('晚') && hour >= 4 && hour < 10)) {
    slot = 'breakfast';
  } else if (clean.includes('晚餐') || clean.includes('晚饭') || (!clean.includes('午') && hour >= 16 && hour < 22)) {
    slot = 'dinner';
  } else if (clean.includes('加餐') || clean.includes('下午茶') || clean.includes('零食') || hour >= 22 || hour < 4) {
    slot = 'snack';
  }

  // 6. 构造 content (丰满详实的输入框内容，保留完整菜品与全部食材，绝不省略截断)
  let mealName = '';
  const mDish = clean.match(/这(?:道|顿|餐|份)(.+?)(?:的搭配|很|非常|做好了|理出来)/);
  if (mDish) {
    mealName = mDish[1].replace(/[:：]/g, '').trim();
  }

  let content = '';
  const contentParts = [];
  if (mealName) {
    contentParts.push(`【${mealName}】`);
  }

  if (items.length > 0) {
    const itemStrings = items.map(it => {
      const p = it.portion ? ` (${it.portion})` : '';
      return `${it.name}${p}`;
    });
    contentParts.push(mealName ? ('食材明细：' + itemStrings.join('、')) : itemStrings.join('、'));
  }

  if (contentParts.length > 0) {
    content = contentParts.join('\n');
  } else {
    const slotNames = { breakfast: '早餐打卡', lunch: '午餐打卡', dinner: '晚餐打卡', snack: '加餐打卡' };
    content = slotNames[slot] || '餐品打卡';
  }

  return { slot, content, calories, protein, carbs, fat, items };
}
